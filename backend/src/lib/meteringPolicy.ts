import { createHmac } from "node:crypto";
import type { LlmModelId } from "./llmClient.js";

export const USAGE_PLAN_VERSION = "monthly-600-v1";
export const CREDIT_TARIFF_VERSION = "public-models-v1";
export const MONTHLY_CREDITS = 600;
export const DAILY_OPERATION_LIMIT = 60;
export const DAILY_PROVIDER_CALL_LIMIT = 200;
export const TASTE_LIFETIME_TURN_LIMIT = 10;

export const PUBLIC_LLM_MODELS = [
  "mistral-small-latest",
  "deepseek-flash",
  "gemini-3.8-flash",
] as const satisfies readonly LlmModelId[];
export type PublicLlmModelId = (typeof PUBLIC_LLM_MODELS)[number];

export const MODEL_CREDIT_COST: Record<PublicLlmModelId, number> = {
  "mistral-small-latest": 1,
  "deepseek-flash": 2,
  "gemini-3.8-flash": 6,
};

export type UsageWarning = "normal" | "low" | "critical" | "empty";

export type UsageSummary = {
  creditsGranted: number;
  creditsRemaining: number;
  periodStart: string | null;
  periodEnd: string | null;
  resetsAt: string | null;
  warning: UsageWarning;
  allowedModels: PublicLlmModelId[];
  creditCost: Record<PublicLlmModelId, number>;
};

export function isUsageEnforcementRequired(): boolean {
  return process.env.USAGE_ENFORCEMENT?.trim().toLowerCase() === "required";
}

export function assertMeteringConfiguration(): void {
  if (isUsageEnforcementRequired() && !process.env.METERING_HMAC_KEY?.trim()) {
    throw new Error("METERING_HMAC_KEY is required when USAGE_ENFORCEMENT=required");
  }
}

export function isPublicLlmModel(model: LlmModelId): model is PublicLlmModelId {
  return (PUBLIC_LLM_MODELS as readonly string[]).includes(model);
}

export function allowedModelsForCredits(remaining: number): PublicLlmModelId[] {
  if (remaining >= 6) {
    return [...PUBLIC_LLM_MODELS];
  }
  if (remaining >= 2) {
    return ["mistral-small-latest", "deepseek-flash"];
  }
  if (remaining >= 1) {
    return ["mistral-small-latest"];
  }
  return [];
}

export function usageWarning(remaining: number): UsageWarning {
  if (remaining <= 0) {
    return "empty";
  }
  if (remaining <= Math.floor(MONTHLY_CREDITS * 0.1)) {
    return "critical";
  }
  if (remaining <= Math.floor(MONTHLY_CREDITS * 0.2)) {
    return "low";
  }
  return "normal";
}

function daysInUtcMonth(year: number, month: number): number {
  return new Date(Date.UTC(year, month + 1, 0)).getUTCDate();
}

/** Adds months from the original UTC anchor, so clamping never accumulates drift. */
export function utcMonthBoundary(anchor: Date, monthOffset: number): Date {
  const absoluteMonth = anchor.getUTCFullYear() * 12 + anchor.getUTCMonth() + monthOffset;
  const year = Math.floor(absoluteMonth / 12);
  const month = ((absoluteMonth % 12) + 12) % 12;
  return new Date(
    Date.UTC(
      year,
      month,
      Math.min(anchor.getUTCDate(), daysInUtcMonth(year, month)),
      anchor.getUTCHours(),
      anchor.getUTCMinutes(),
      anchor.getUTCSeconds(),
      anchor.getUTCMilliseconds(),
    ),
  );
}

export function paidUsagePeriod(anchor: Date, at: Date): { startsAt: Date; endsAt: Date } {
  let offset =
    (at.getUTCFullYear() - anchor.getUTCFullYear()) * 12 +
    (at.getUTCMonth() - anchor.getUTCMonth());
  if (utcMonthBoundary(anchor, offset) > at) {
    offset -= 1;
  }
  return {
    startsAt: utcMonthBoundary(anchor, offset),
    endsAt: utcMonthBoundary(anchor, offset + 1),
  };
}

export function developmentUsagePeriod(at: Date): { startsAt: Date; endsAt: Date } {
  return {
    startsAt: new Date(Date.UTC(at.getUTCFullYear(), at.getUTCMonth(), 1)),
    endsAt: new Date(Date.UTC(at.getUTCFullYear(), at.getUTCMonth() + 1, 1)),
  };
}

function canonicalValue(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(canonicalValue);
  }
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([key, nested]) => [key, canonicalValue(nested)]),
    );
  }
  return value;
}

export function canonicalJson(value: unknown): string {
  return JSON.stringify(canonicalValue(value));
}

function meteringHmacKey(): string {
  const configured = process.env.METERING_HMAC_KEY?.trim();
  if (configured) {
    return configured;
  }
  if (!isUsageEnforcementRequired() || process.env.VITEST === "true") {
    return "local-only-metering-hmac-key";
  }
  throw new Error("METERING_HMAC_KEY is required");
}

export function requestFingerprint(request: unknown, model: LlmModelId): string {
  return createHmac("sha256", meteringHmacKey())
    .update(canonicalJson({ request, model }))
    .digest("hex");
}
