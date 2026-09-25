import { randomUUID } from "node:crypto";
import type postgres from "postgres";
import type { LlmModelId } from "../lib/llmClient.js";
import type { LlmUsageEvent } from "../lib/llmUsage.js";
import {
  CREDIT_TARIFF_VERSION,
  DAILY_OPERATION_LIMIT,
  DAILY_PROVIDER_CALL_LIMIT,
  MODEL_CREDIT_COST,
  MONTHLY_CREDITS,
  TASTE_LIFETIME_TURN_LIMIT,
  USAGE_PLAN_VERSION,
  allowedModelsForCredits,
  developmentUsagePeriod,
  isPublicLlmModel,
  isUsageEnforcementRequired,
  paidUsagePeriod,
  usageWarning,
  type PublicLlmModelId,
  type UsageSummary,
} from "../lib/meteringPolicy.js";
import { getSql, wrapDbError } from "./client.js";

const OPERATION_LEASE_MS = 30_000;
const BURST_OPERATION_LIMIT = 10;
const BURST_WINDOW_MS = 60_000;

type OperationKind = "full" | "recook";
type TerminalState = "ready" | "continue" | "failed";

type PeriodRow = {
  id: string;
  starts_at: Date | string;
  ends_at: Date | string;
  granted_credits: number;
  reserved_credits: number;
  charged_credits: number;
};

type EntitlementContext = {
  taste_completed_at: Date | string | null;
  taste_consumed_at: Date | string | null;
  entitlement_user_id: string | null;
  status: string | null;
  paid_through: Date | string | null;
  grace_period_expires_at: Date | string | null;
  revoked_at: Date | string | null;
  quota_anchor: Date | string | null;
};

export class MeteringError extends Error {
  readonly status: 400 | 402 | 409 | 429;
  readonly code: string;
  readonly usage?: UsageSummary;

  constructor(
    message: string,
    code: string,
    status: 400 | 402 | 409 | 429,
    usage?: UsageSummary,
  ) {
    super(message);
    this.name = "MeteringError";
    this.status = status;
    this.code = code;
    this.usage = usage;
  }
}

export type StartedMeterOperation = {
  operationId: string;
  ownerId: string;
  model: LlmModelId;
  taste: boolean;
  usage: UsageSummary;
};

function utcDate(date: Date): string {
  return date.toISOString().slice(0, 10);
}

function sqlTimestamp(date: Date): string {
  return date.toISOString();
}

function asDate(value: Date | string): Date {
  return value instanceof Date ? value : new Date(value);
}

function summaryForPeriod(period: PeriodRow): UsageSummary {
  const remaining =
    period.granted_credits - period.reserved_credits - period.charged_credits;
  return {
    creditsGranted: period.granted_credits,
    creditsRemaining: remaining,
    periodStart: asDate(period.starts_at).toISOString(),
    periodEnd: asDate(period.ends_at).toISOString(),
    resetsAt: asDate(period.ends_at).toISOString(),
    warning: usageWarning(remaining),
    allowedModels: allowedModelsForCredits(remaining),
    creditCost: { ...MODEL_CREDIT_COST },
  };
}

function tasteSummary(available = true): UsageSummary {
  return {
    creditsGranted: 0,
    creditsRemaining: 0,
    periodStart: null,
    periodEnd: null,
    resetsAt: null,
    warning: "empty",
    allowedModels: available ? ["mistral-small-latest"] : [],
    creditCost: { ...MODEL_CREDIT_COST },
  };
}

async function expireStaleForOwner(
  tx: postgres.TransactionSql,
  ownerId: string,
  now: Date,
): Promise<void> {
  const expired = await tx<{ period_id: string | null; reserved_credits: number }[]>`
    update meter_operations
    set state = 'expired', result_kind = null, updated_at = ${sqlTimestamp(now)}
    where owner_id = ${ownerId}
      and state = 'running'
      and lease_expires_at <= ${sqlTimestamp(now)}
    returning period_id, reserved_credits
  `;
  for (const operation of expired) {
    if (operation.period_id && operation.reserved_credits > 0) {
      await tx`
        update usage_periods
        set reserved_credits = reserved_credits - ${operation.reserved_credits},
            updated_at = ${sqlTimestamp(now)}
        where id = ${operation.period_id}
      `;
    }
  }
}

function entitlementIsActive(row: EntitlementContext, now: Date): boolean {
  if (
    row.entitlement_user_id === null ||
    row.revoked_at !== null ||
    row.paid_through === null
  ) {
    return false;
  }
  if (row.status === "active") {
    return asDate(row.paid_through) > now;
  }
  if (row.status === "grace") {
    return (
      row.grace_period_expires_at !== null &&
      asDate(row.grace_period_expires_at) > now
    );
  }
  return row.status === "billing_retry";
}

async function ensurePeriod(
  tx: postgres.TransactionSql,
  ownerId: string,
  entitlement: EntitlementContext,
  now: Date,
): Promise<PeriodRow | null> {
  const active = entitlementIsActive(entitlement, now);
  if (!active && isUsageEnforcementRequired()) {
    return null;
  }

  const paidThrough = entitlement.paid_through
    ? asDate(entitlement.paid_through)
    : null;
  const quotaDate =
    active &&
    paidThrough &&
    paidThrough <= now &&
    (entitlement.status === "grace" || entitlement.status === "billing_retry")
      ? new Date(paidThrough.getTime() - 1)
      : now;
  const range =
    active && entitlement.quota_anchor
      ? paidUsagePeriod(asDate(entitlement.quota_anchor), quotaDate)
      : developmentUsagePeriod(now);
  if (
    active &&
    (!paidThrough || paidThrough <= range.startsAt)
  ) {
    return null;
  }

  await tx`
    insert into usage_periods (
      owner_id, entitlement_user_id, starts_at, ends_at, granted_credits,
      plan_version, tariff_version
    ) values (
      ${ownerId},
      ${active ? entitlement.entitlement_user_id : null},
      ${sqlTimestamp(range.startsAt)},
      ${sqlTimestamp(range.endsAt)},
      ${MONTHLY_CREDITS},
      ${USAGE_PLAN_VERSION},
      ${CREDIT_TARIFF_VERSION}
    )
    on conflict (owner_id, starts_at) do nothing
  `;
  const rows = await tx<PeriodRow[]>`
    select id, starts_at, ends_at, granted_credits, reserved_credits, charged_credits
    from usage_periods
    where owner_id = ${ownerId} and starts_at = ${sqlTimestamp(range.startsAt)}
    for update
  `;
  return rows[0] ?? null;
}

export async function startMeterOperation(input: {
  ownerId: string;
  clientRequestId: string;
  requestFingerprint: string;
  model: LlmModelId;
  kind: OperationKind;
  now?: Date;
}): Promise<StartedMeterOperation> {
  const now = input.now ?? new Date();
  try {
    return await getSql().begin(async (tx) => {
      await tx`select pg_advisory_xact_lock(hashtextextended(${input.ownerId}, 0))`;
      await expireStaleForOwner(tx, input.ownerId, now);

      const duplicates = await tx<
        { request_fingerprint: string; state: string }[]
      >`
        select request_fingerprint, state
        from meter_operations
        where owner_id = ${input.ownerId} and client_request_id = ${input.clientRequestId}
      `;
      const duplicate = duplicates[0];
      if (duplicate) {
        if (duplicate.request_fingerprint !== input.requestFingerprint) {
          throw new MeteringError(
            "Idempotency key was already used for a different request",
            "IDEMPOTENCY_CONFLICT",
            409,
          );
        }
        if (duplicate.state === "running") {
          throw new MeteringError("This operation is still running", "OPERATION_RUNNING", 409);
        }
        throw new MeteringError(
          "This request was already completed",
          "REQUEST_ALREADY_COMPLETED",
          409,
        );
      }

      const running = await tx<{ id: string }[]>`
        select id from meter_operations
        where owner_id = ${input.ownerId} and state = 'running'
        limit 1
      `;
      if (running.length > 0) {
        throw new MeteringError("Another operation is still running", "OPERATION_RUNNING", 409);
      }

      const recent = await tx<{ count: number }[]>`
        select count(*)::int as count
        from meter_operations
        where owner_id = ${input.ownerId}
          and created_at > ${sqlTimestamp(new Date(now.getTime() - BURST_WINDOW_MS))}
      `;
      if ((recent[0]?.count ?? 0) >= BURST_OPERATION_LIMIT) {
        throw new MeteringError("Too many recent operations", "OPERATION_RATE_LIMIT", 429);
      }

      const dailyRows = await tx<
        { operation_count: number; provider_call_count: number }[]
      >`
        insert into daily_usage (owner_id, usage_date)
        values (${input.ownerId}, ${utcDate(now)})
        on conflict (owner_id, usage_date) do update set updated_at = ${sqlTimestamp(now)}
        returning operation_count, provider_call_count
      `;
      if ((dailyRows[0]?.operation_count ?? 0) >= DAILY_OPERATION_LIMIT) {
        throw new MeteringError(
          "Daily operation limit reached",
          "DAILY_OPERATION_LIMIT",
          429,
        );
      }

      const contexts = await tx<EntitlementContext[]>`
        select
          u.taste_completed_at,
          u.taste_consumed_at,
          e.user_id as entitlement_user_id,
          e.status,
          e.paid_through,
          e.grace_period_expires_at,
          e.revoked_at,
          e.quota_anchor
        from users u
        left join subscription_entitlements e on e.user_id = u.id
        where u.id = ${input.ownerId}
        for update of u
      `;
      const context = contexts[0];
      if (!context) {
        throw new MeteringError("Sign in required", "UNAUTHENTICATED", 400);
      }

      const period = await ensurePeriod(tx, input.ownerId, context, now);
      const taste =
        period === null &&
        context.taste_completed_at === null &&
        context.taste_consumed_at === null;
      if (!period && !taste) {
        if (
          context.taste_consumed_at !== null &&
          context.taste_completed_at === null
        ) {
          throw new MeteringError(
            "Free taste was already consumed",
            "TASTE_ALREADY_CONSUMED",
            402,
            tasteSummary(false),
          );
        }
        throw new MeteringError(
          "An active subscription is required",
          "SUBSCRIPTION_REQUIRED",
          402,
        );
      }

      let reservedCredits = 0;
      let usage: UsageSummary;
      if (taste) {
        usage = tasteSummary();
        if (input.kind === "recook") {
          throw new MeteringError(
            "Recook is unavailable during the free taste",
            "TASTE_RECOOK_UNAVAILABLE",
            402,
            usage,
          );
        }
        if (input.model !== "mistral-small-latest") {
          throw new MeteringError(
            "Only Mistral is available during the free taste",
            "MODEL_NOT_AVAILABLE",
            402,
            usage,
          );
        }
        const tastes = await tx<{ client_turn_count: number }[]>`
          insert into taste_usage (owner_id, client_turn_count, ready_count, updated_at)
          values (${input.ownerId}, 0, 0, ${sqlTimestamp(now)})
          on conflict (owner_id) do update set updated_at = ${sqlTimestamp(now)}
          returning client_turn_count
        `;
        if ((tastes[0]?.client_turn_count ?? 0) >= TASTE_LIFETIME_TURN_LIMIT) {
          throw new MeteringError(
            "Free taste limit reached",
            "TASTE_LIMIT_REACHED",
            402,
            tasteSummary(false),
          );
        }
        await tx`
          update taste_usage
          set client_turn_count = client_turn_count + 1, updated_at = ${sqlTimestamp(now)}
          where owner_id = ${input.ownerId}
        `;
      } else {
        if (!period) {
          throw new Error("period invariant");
        }
        usage = summaryForPeriod(period);
        if (!isPublicLlmModel(input.model)) {
          throw new MeteringError(
            "That model is unavailable",
            "MODEL_NOT_AVAILABLE",
            402,
            usage,
          );
        }
        reservedCredits = MODEL_CREDIT_COST[input.model];
        if (!usage.allowedModels.includes(input.model)) {
          throw new MeteringError(
            "Not enough credits for that model",
            "INSUFFICIENT_CREDITS",
            402,
            usage,
          );
        }
        await tx`
          update usage_periods
          set reserved_credits = reserved_credits + ${reservedCredits}, updated_at = ${sqlTimestamp(now)}
          where id = ${period.id}
        `;
        usage = {
          ...usage,
          creditsRemaining: usage.creditsRemaining - reservedCredits,
          warning: usageWarning(usage.creditsRemaining - reservedCredits),
          allowedModels: allowedModelsForCredits(usage.creditsRemaining - reservedCredits),
        };
      }

      const operationId = randomUUID();
      await tx`
        insert into meter_operations (
          id, owner_id, client_request_id, request_fingerprint, period_id, model,
          kind, reserved_credits, state, lease_expires_at, created_at, updated_at
        ) values (
          ${operationId}, ${input.ownerId}, ${input.clientRequestId},
          ${input.requestFingerprint}, ${period?.id ?? null}, ${input.model},
          ${input.kind}, ${reservedCredits}, 'running',
          ${sqlTimestamp(new Date(now.getTime() + OPERATION_LEASE_MS))},
          ${sqlTimestamp(now)}, ${sqlTimestamp(now)}
        )
      `;
      await tx`
        update daily_usage
        set operation_count = operation_count + 1, updated_at = ${sqlTimestamp(now)}
        where owner_id = ${input.ownerId} and usage_date = ${utcDate(now)}
      `;
      return {
        operationId,
        ownerId: input.ownerId,
        model: input.model,
        taste,
        usage,
      };
    });
  } catch (error) {
    if (error instanceof MeteringError) {
      throw error;
    }
    throw wrapDbError(error, "start_meter_operation");
  }
}

export async function beginProviderCall(
  operation: StartedMeterOperation,
  now: Date = new Date(),
): Promise<void> {
  try {
    await getSql().begin(async (tx) => {
      await tx`select pg_advisory_xact_lock(hashtextextended(${operation.ownerId}, 0))`;
      const rows = await tx<{ state: string; lease_expires_at: Date | string }[]>`
        select state, lease_expires_at
        from meter_operations
        where id = ${operation.operationId} and owner_id = ${operation.ownerId}
        for update
      `;
      const row = rows[0];
      if (!row || row.state !== "running" || asDate(row.lease_expires_at) <= now) {
        throw new MeteringError("Operation lease expired", "OPERATION_EXPIRED", 409);
      }
      const daily = await tx<{ provider_call_count: number }[]>`
        insert into daily_usage (owner_id, usage_date, provider_call_count, updated_at)
        values (${operation.ownerId}, ${utcDate(now)}, 0, ${sqlTimestamp(now)})
        on conflict (owner_id, usage_date) do update set updated_at = ${sqlTimestamp(now)}
        returning provider_call_count
      `;
      if ((daily[0]?.provider_call_count ?? 0) >= DAILY_PROVIDER_CALL_LIMIT) {
        throw new MeteringError(
          "Daily provider-call limit reached",
          "PROVIDER_CALL_LIMIT",
          429,
          operation.usage,
        );
      }
      await tx`
        update daily_usage
        set provider_call_count = provider_call_count + 1, updated_at = ${sqlTimestamp(now)}
        where owner_id = ${operation.ownerId} and usage_date = ${utcDate(now)}
      `;
    });
  } catch (error) {
    if (error instanceof MeteringError) {
      throw error;
    }
    throw wrapDbError(error, "begin_provider_call");
  }
}

export async function beginStandaloneProviderCall(
  ownerId: string,
  now: Date = new Date(),
): Promise<void> {
  try {
    await getSql().begin(async (tx) => {
      await tx`select pg_advisory_xact_lock(hashtextextended(${ownerId}, 0))`;
      const rows = await tx<{ provider_call_count: number }[]>`
        insert into daily_usage (owner_id, usage_date, provider_call_count, updated_at)
        values (${ownerId}, ${utcDate(now)}, 0, ${sqlTimestamp(now)})
        on conflict (owner_id, usage_date) do update set updated_at = ${sqlTimestamp(now)}
        returning provider_call_count
      `;
      if ((rows[0]?.provider_call_count ?? 0) >= DAILY_PROVIDER_CALL_LIMIT) {
        throw new MeteringError(
          "Daily provider-call limit reached",
          "PROVIDER_CALL_LIMIT",
          429,
        );
      }
      await tx`
        update daily_usage
        set provider_call_count = provider_call_count + 1, updated_at = ${sqlTimestamp(now)}
        where owner_id = ${ownerId} and usage_date = ${utcDate(now)}
      `;
    });
  } catch (error) {
    if (error instanceof MeteringError) {
      throw error;
    }
    throw wrapDbError(error, "begin_standalone_provider_call");
  }
}

export async function finishMeterOperation(input: {
  operation: StartedMeterOperation;
  state: TerminalState;
  resultKind?: "ready" | "continue";
  usageEvents: readonly LlmUsageEvent[];
  now?: Date;
}): Promise<UsageSummary> {
  const now = input.now ?? new Date();
  try {
    return await getSql().begin(async (tx) => {
      await tx`select pg_advisory_xact_lock(hashtextextended(${input.operation.ownerId}, 0))`;
      const operations = await tx<
        { period_id: string | null; reserved_credits: number; state: string }[]
      >`
        select period_id, reserved_credits, state
        from meter_operations
        where id = ${input.operation.operationId} and owner_id = ${input.operation.ownerId}
        for update
      `;
      const operation = operations[0];
      if (!operation || operation.state !== "running") {
        return getUsageSummaryInTransaction(tx, input.operation.ownerId, now);
      }

      for (const event of input.usageEvents) {
        await tx`
          insert into llm_call_usage (
            operation_id, owner_id, call_kind, attempt, requested_model, returned_model,
            provider_request_id, status, prompt_tokens, cached_tokens, cache_hit_tokens,
            cache_miss_tokens, completion_tokens, thinking_tokens, tool_tokens,
            usage_source, rate_version, company_cost_nano_usd, created_at
          ) values (
            ${input.operation.operationId}, ${input.operation.ownerId}, ${event.callKind},
            ${event.attempt}, ${event.requestedModel}, ${event.returnedModel},
            ${event.providerRequestId ?? null}, ${event.status}, ${event.promptTokens},
            ${event.cachedTokens}, ${event.cacheHitTokens}, ${event.cacheMissTokens},
            ${event.completionTokens}, ${event.thinkingTokens}, ${event.toolTokens},
            ${event.usageSource}, ${event.rateVersion},
            ${event.companyCostNanoUsd.toString()}::bigint, ${sqlTimestamp(now)}
          )
        `;
      }

      const charge = input.state === "ready" ? operation.reserved_credits : 0;
      if (operation.period_id) {
        await tx`
          update usage_periods
          set reserved_credits = reserved_credits - ${operation.reserved_credits},
              charged_credits = charged_credits + ${charge},
              updated_at = ${sqlTimestamp(now)}
          where id = ${operation.period_id}
        `;
      } else if (input.state === "ready") {
        const consumed = await tx<{ id: string }[]>`
          update users
          set taste_consumed_at = ${sqlTimestamp(now)}, updated_at = ${sqlTimestamp(now)}
          where id = ${input.operation.ownerId}
            and taste_consumed_at is null
            and taste_completed_at is null
          returning id
        `;
        if (consumed.length === 0) {
          throw new MeteringError(
            "Free taste was already consumed",
            "TASTE_ALREADY_CONSUMED",
            402,
            tasteSummary(false),
          );
        }
        await tx`
          update taste_usage
          set ready_count = ready_count + 1, updated_at = ${sqlTimestamp(now)}
          where owner_id = ${input.operation.ownerId}
        `;
      }
      await tx`
        update meter_operations
        set state = ${input.state},
            charged_credits = ${charge},
            result_kind = ${input.resultKind ?? null},
            updated_at = ${sqlTimestamp(now)}
        where id = ${input.operation.operationId}
      `;
      return getUsageSummaryInTransaction(tx, input.operation.ownerId, now);
    });
  } catch (error) {
    if (error instanceof MeteringError) {
      throw error;
    }
    throw wrapDbError(error, "finish_meter_operation");
  }
}

async function getUsageSummaryInTransaction(
  tx: postgres.TransactionSql,
  ownerId: string,
  now: Date,
): Promise<UsageSummary> {
  const contexts = await tx<EntitlementContext[]>`
    select
      u.taste_completed_at,
      u.taste_consumed_at,
      e.user_id as entitlement_user_id,
      e.status,
      e.paid_through,
      e.grace_period_expires_at,
      e.revoked_at,
      e.quota_anchor
    from users u
    left join subscription_entitlements e on e.user_id = u.id
    where u.id = ${ownerId}
  `;
  const context = contexts[0];
  if (!context) {
    throw new MeteringError("Sign in required", "UNAUTHENTICATED", 400);
  }
  const period = await ensurePeriod(tx, ownerId, context, now);
  if (period) {
    return summaryForPeriod(period);
  }
  if (context.taste_completed_at !== null || context.taste_consumed_at !== null) {
    return tasteSummary(false);
  }
  const tastes = await tx<{ client_turn_count: number }[]>`
    select client_turn_count from taste_usage where owner_id = ${ownerId}
  `;
  return tasteSummary((tastes[0]?.client_turn_count ?? 0) < TASTE_LIFETIME_TURN_LIMIT);
}

export async function getUsageSummary(
  ownerId: string,
  now: Date = new Date(),
): Promise<UsageSummary> {
  try {
    return await getSql().begin(async (tx) => {
      await tx`select pg_advisory_xact_lock(hashtextextended(${ownerId}, 0))`;
      await expireStaleForOwner(tx, ownerId, now);
      return getUsageSummaryInTransaction(tx, ownerId, now);
    });
  } catch (error) {
    if (error instanceof MeteringError) {
      throw error;
    }
    throw wrapDbError(error, "get_usage_summary");
  }
}

export async function expireStaleOperations(
  ownerId: string,
  now: Date = new Date(),
): Promise<void> {
  try {
    await getSql().begin(async (tx) => {
      await tx`select pg_advisory_xact_lock(hashtextextended(${ownerId}, 0))`;
      await expireStaleForOwner(tx, ownerId, now);
    });
  } catch (error) {
    throw wrapDbError(error, "expire_stale_operations");
  }
}

export const CREDIT_ADJUSTMENT_REASONS = [
  "support_grant",
  "billing_correction",
  "incident_credit",
  "test",
] as const;
export type CreditAdjustmentReason = (typeof CREDIT_ADJUSTMENT_REASONS)[number];

export async function applyCreditAdjustment(input: {
  ownerId: string;
  periodId: string;
  deltaCredits: number;
  reasonCode: CreditAdjustmentReason;
  operatorRef?: string;
  now?: Date;
}): Promise<UsageSummary> {
  if (!Number.isInteger(input.deltaCredits) || input.deltaCredits === 0) {
    throw new Error("deltaCredits must be a non-zero integer");
  }
  const now = input.now ?? new Date();
  try {
    return await getSql().begin(async (tx) => {
      await tx`select pg_advisory_xact_lock(hashtextextended(${input.ownerId}, 0))`;
      const changed = await tx<{ id: string }[]>`
        update usage_periods
        set granted_credits = granted_credits + ${input.deltaCredits},
            updated_at = ${sqlTimestamp(now)}
        where id = ${input.periodId}
          and owner_id = ${input.ownerId}
          and granted_credits + ${input.deltaCredits} >= reserved_credits + charged_credits
        returning id
      `;
      if (changed.length === 0) {
        throw new Error("Adjustment would reduce allowance below committed credits");
      }
      await tx`
        insert into credit_adjustments (
          owner_id, period_id, delta_credits, reason_code, operator_ref, created_at
        ) values (
          ${input.ownerId}, ${input.periodId}, ${input.deltaCredits},
          ${input.reasonCode}, ${input.operatorRef ?? null}, ${sqlTimestamp(now)}
        )
      `;
      return getUsageSummaryInTransaction(tx, input.ownerId, now);
    });
  } catch (error) {
    throw wrapDbError(error, "apply_credit_adjustment");
  }
}

export async function recordStandaloneLlmUsage(input: {
  ownerId?: string;
  event: LlmUsageEvent;
  now?: Date;
}): Promise<void> {
  const now = input.now ?? new Date();
  try {
    await getSql()`
      insert into llm_call_usage (
        operation_id, owner_id, call_kind, attempt, requested_model, returned_model,
        provider_request_id, status, prompt_tokens, cached_tokens, cache_hit_tokens,
        cache_miss_tokens, completion_tokens, thinking_tokens, tool_tokens,
        usage_source, rate_version, company_cost_nano_usd, created_at
      ) values (
        null, ${input.ownerId ?? null}, ${input.event.callKind}, ${input.event.attempt},
        ${input.event.requestedModel}, ${input.event.returnedModel},
        ${input.event.providerRequestId ?? null}, ${input.event.status},
        ${input.event.promptTokens}, ${input.event.cachedTokens},
        ${input.event.cacheHitTokens}, ${input.event.cacheMissTokens},
        ${input.event.completionTokens}, ${input.event.thinkingTokens},
        ${input.event.toolTokens}, ${input.event.usageSource}, ${input.event.rateVersion},
        ${input.event.companyCostNanoUsd.toString()}::bigint, ${sqlTimestamp(now)}
      )
    `;
  } catch (error) {
    throw wrapDbError(error, "record_standalone_llm_usage");
  }
}
