import { randomUUID } from "node:crypto";
import { zValidator } from "@hono/zod-validator";
import { Hono } from "hono";
import { z } from "zod";
import { DbError } from "../db/client.js";
import {
  beginProviderCall,
  findReframeReplay,
  finishMeterOperation,
  getUsageSummary,
  MeteringError,
  startMeterOperation,
  type StartedMeterOperation,
} from "../db/metering.js";
import { getOwnerUserId, requireAuth } from "../lib/authStub.js";
import { FORCE_READY_AFTER, recookStyle, writeCook, type CookCallOptions } from "../lib/cook.js";
import { signedMetaSchema } from "../lib/cookSchema.js";
import { signCook, signResult, verifyCook } from "../lib/cookSignature.js";
import { crisisMessage, crisisResourceLine } from "../lib/crisisResources.js";
import { runDecision, solemnSkipFor } from "../lib/decision.js";
import { shownStyleSchema, stylesForRequest } from "../lib/styleSet.js";
import { errorBody, validationErrorMessage } from "../lib/http.js";
import {
  COOK_DEADLINE_MS,
  LLM_MODEL_IDS,
  LlmError,
  modelsForStep,
  type LlmModelId,
  type StepModels,
} from "../lib/llmClient.js";
import type { LlmUsageEvent } from "../lib/llmUsage.js";
import {
  COOK_CREDIT_COST,
  isUsageEnforcementRequired,
  requestFingerprint,
  type UsageSummary,
} from "../lib/meteringPolicy.js";
import { openReplay, parseReplayKey, REPLAY_KEY_HEADER, sealReplay } from "../lib/reframeReplay.js";
import {
  matchingFor,
  type ContinueResponse,
  type FollowUpAnswer,
  type ReadyResponse,
  type ReframeMeta,
  type ReframeResponse,
  type ReframeUsage,
  type SafetyFlag,
} from "../types/index.js";

const MAX_TEXT_LENGTH = 2000;
const MAX_REFRAME_LENGTH = 4000;
/** The model drives the exchange; this is an abuse guard, not a script length. */
const MAX_FOLLOW_UPS = 6;

const followUpSchema = z.object({
  question: z
    .string()
    .transform((value) => value.trim())
    .pipe(z.string().min(1, "question must not be empty").max(1000)),
  answer: z
    .string()
    .transform((value) => value.trim())
    .pipe(
      z
        .string()
        .min(1, "answer must not be empty")
        .max(MAX_TEXT_LENGTH, `answer must be at most ${MAX_TEXT_LENGTH} characters`),
    ),
});

const trimmedText = (label: string, max: number) =>
  z
    .string()
    .transform((value) => value.trim())
    .pipe(
      z
        .string()
        .min(1, `${label} must not be empty`)
        .max(max, `${label} must be at most ${max} characters`),
    );

const recookSchema = z
  .object({
    style: shownStyleSchema(),
    cook: z
      .object({
        thought: trimmedText("thought", MAX_TEXT_LENGTH),
        thoughtOriginal: trimmedText("thoughtOriginal", MAX_TEXT_LENGTH).optional(),
        meta: signedMetaSchema,
        model: z.enum(LLM_MODEL_IDS),
        signature: z.string().min(1).max(128),
      })
      .strict(),
    previous: z
      .object({
        reframe: trimmedText("previous reframe", MAX_REFRAME_LENGTH),
        reframeOriginal: trimmedText("previous reframeOriginal", MAX_REFRAME_LENGTH).optional(),
        signature: z.string().min(1).max(128),
      })
      .strict()
      .optional(),
  })
  .strict();

const reframeRequestSchema = z
  .object({
    text: trimmedText("text", MAX_TEXT_LENGTH).optional(),
    followUps: z
      .array(followUpSchema)
      .max(MAX_FOLLOW_UPS, `followUps must contain at most ${MAX_FOLLOW_UPS} entries`)
      .optional(),
    recook: recookSchema.optional(),
    // Lenient on purpose: a malformed region must never block a crisis turn. It only
    // falls back to the generic contact line.
    region: z
      .unknown()
      .optional()
      .transform((value) =>
        typeof value === "string" && /^[A-Za-z]{2}$/.test(value) ? value.toUpperCase() : undefined,
      ),
  })
  .strict()
  .superRefine((body, ctx) => {
    if ((body.text === undefined) === (body.recook === undefined)) {
      ctx.addIssue({ code: "custom", message: "send either text or recook" });
    }
    if (body.recook !== undefined && body.followUps !== undefined) {
      ctx.addIssue({ code: "custom", message: "a recook has no followUps" });
    }
  });

type RecookInput = z.infer<typeof recookSchema>;

/** A recook only starts from a cook this server signed for this account, previous answer included. */
function verifiedRecook(ownerId: string, recook: RecookInput): boolean {
  const { cook, previous, style } = recook;
  return (
    cook.meta.safety === "none" &&
    verifyCook({
      ownerId,
      thought: cook.thought,
      thoughtOriginal: cook.thoughtOriginal,
      model: cook.model,
      meta: cook.meta,
      signature: cook.signature,
      results: previous ? [{ style, ...previous }] : [],
    })
  );
}

/** Every `continue` is built here, so a safety turn always carries local contacts and no chips. */
function continueBody(
  turn: { message: string; options: string[]; safety: SafetyFlag },
  region: string | undefined,
): Omit<ContinueResponse, "usage"> {
  if (turn.safety === "none") {
    return { kind: "continue", message: turn.message, options: turn.options, safety: "none" };
  }
  return {
    kind: "continue",
    message: crisisMessage(turn.message),
    options: [],
    safety: turn.safety,
    crisisResource: crisisResourceLine(region),
  };
}

/** A response before its `usage`, which is what a replay stores. */
type ReframePayload = Omit<ContinueResponse, "usage"> | Omit<ReadyResponse, "usage">;

/**
 * A retry of a finished request gets the response it already paid for, with the balance
 * as it is now. Null when there is nothing to replay, which leaves the original 409.
 */
async function replayCompleted(input: {
  ownerId: string;
  clientRequestId: string;
  requestFingerprint: string;
  replayKey: Buffer;
}): Promise<ReframeResponse | null> {
  const stored = await findReframeReplay(input);
  if (!stored) {
    return null;
  }
  const payload = openReplay(input.replayKey, stored.operationId, stored.sealed);
  if (payload === null || typeof payload !== "object") {
    return null;
  }
  const summary = await getUsageSummary(input.ownerId);
  return {
    ...(payload as ReframePayload),
    usage: responseUsage(summary, stored.chargedCredits),
  };
}

export const reframeRoute = new Hono();

function responseUsage(summary: UsageSummary, creditsUsed: number): ReframeUsage {
  return {
    creditsUsed,
    remaining: summary.creditsRemaining,
    granted: summary.creditsGranted,
    resetsAt: summary.resetsAt,
    warning: summary.warning,
    creditCost: summary.creditCost,
    plan: summary.plan,
  };
}

function meteringErrorResponse(error: MeteringError): Record<string, unknown> {
  return {
    ...errorBody(error.message, error.code),
    ...(error.usage
      ? {
          creditsRemaining: error.usage.creditsRemaining,
          creditsGranted: error.usage.creditsGranted,
          resetsAt: error.usage.resetsAt,
        }
      : {}),
  };
}

reframeRoute.post(
  "/",
  requireAuth,
  zValidator("json", reframeRequestSchema, (result, c) => {
    if (!result.success) {
      return c.json(errorBody(validationErrorMessage(result.error), "VALIDATION_ERROR"), 400);
    }
  }),
  async (c) => {
    const validated = c.req.valid("json");
    const { recook } = validated;
    const followUps: FollowUpAnswer[] = validated.followUps ?? [];
    const deadlineAt = Date.now() + COOK_DEADLINE_MS;
    const abortSignal = c.req.raw.signal;
    const ownerId = getOwnerUserId();
    if (recook && !verifiedRecook(ownerId, recook)) {
      return c.json(errorBody("recook does not match a reframe from this server", "VALIDATION_ERROR"), 400);
    }
    let decisionModels: StepModels;
    let writerModels: StepModels;
    try {
      decisionModels = modelsForStep("decision");
      writerModels = modelsForStep("writer");
    } catch {
      return c.json(errorBody("Failed to generate reframe", "LLM_ERROR"), 500);
    }
    const headerKey = c.req.header("Idempotency-Key");
    const parsedKey = headerKey ? z.uuid().safeParse(headerKey) : null;
    if (isUsageEnforcementRequired() && !headerKey) {
      return c.json(errorBody("Idempotency-Key UUID is required", "IDEMPOTENCY_KEY_REQUIRED"), 400);
    }
    if (headerKey && !parsedKey?.success) {
      return c.json(errorBody("Idempotency-Key must be a UUID", "INVALID_IDEMPOTENCY_KEY"), 400);
    }
    const clientRequestId =
      parsedKey?.success
        ? parsedKey.data
        : randomUUID();
    const fingerprint = requestFingerprint(validated);
    const replayKey = parseReplayKey(c.req.header(REPLAY_KEY_HEADER));
    const usageEvents: LlmUsageEvent[] = [];
    let operation: StartedMeterOperation | undefined;

    try {
      const startedOperation = await startMeterOperation({
        ownerId,
        clientRequestId,
        requestFingerprint: fingerprint,
        model: writerModels.primary,
        kind: recook ? "recook" : "full",
      });
      operation = startedOperation;
      const meteredCallOptions = {
        beforeProviderCall: () => beginProviderCall(startedOperation),
        usageSink: (event: LlmUsageEvent) => usageEvents.push(event),
      };
      const finish = async (
        payload: ReframePayload,
        state: "ready" | "continue",
      ): Promise<ReframeResponse> => {
        const summary = await finishMeterOperation({
          operation: startedOperation,
          state,
          resultKind: state,
          usageEvents,
          ...(replayKey ? { replay: sealReplay(replayKey, startedOperation.operationId, payload) } : {}),
        });
        const creditsUsed = state === "continue" || startedOperation.taste ? 0 : COOK_CREDIT_COST;
        return { ...payload, usage: responseUsage(summary, creditsUsed) };
      };

      let answeredBy: LlmModelId = writerModels.primary;
      const options: CookCallOptions = {
        deadlineAt,
        abortSignal,
        model: writerModels.primary,
        fallbackModel: writerModels.fallback,
        onAnsweredBy: (model) => {
          answeredBy = model;
        },
        ...meteredCallOptions,
      };

      if (recook) {
        const { cook, style, previous } = recook;
        // A style the cook held back gets its reason, with no model call and no charge.
        const skipped =
          cook.meta.skippedStyles.find((item) => item.style === style) ?? solemnSkipFor(style, cook);
        if (skipped) {
          const payload = continueBody({ message: skipped.reason, options: [], safety: "none" }, validated.region);
          return c.json(await finish(payload, "continue"));
        }
        const meta: ReframeMeta = { ...cook.meta, matching: matchingFor(cook.meta) };
        const result = await recookStyle(
          { thought: cook.thought, thoughtOriginal: cook.thoughtOriginal, meta },
          style,
          previous?.reframe,
          options,
        );
        const payload: ReframePayload = {
          kind: "ready",
          thought: cook.thought,
          ...(cook.thoughtOriginal ? { thoughtOriginal: cook.thoughtOriginal } : {}),
          results: [
            {
              ...result,
              signature: signResult(ownerId, cook.thought, style, result.reframe, result.reframeOriginal),
            },
          ],
          meta,
          // The cook's own writer and signature stand; a result signature never names a model.
          model: cook.model,
          signature: cook.signature,
        };
        return c.json(await finish(payload, "ready"));
      }

      const text = validated.text;
      if (text === undefined) {
        throw new LlmError("compose turn without text");
      }
      const decided = await runDecision({
        text,
        followUps,
        catalog: stylesForRequest(),
        model: decisionModels.primary,
        fallbackModel: decisionModels.fallback,
        forceReady: followUps.length >= FORCE_READY_AFTER,
        deadlineAt,
        abortSignal,
        ...meteredCallOptions,
      });

      if (decided.kind === "continue") {
        return c.json(await finish(continueBody(decided, validated.region), "continue"));
      }

      // The guard can turn the decision solemn, so the signed meta comes from its result.
      const { decision, results } = await writeCook(decided, options);
      const payload: ReframePayload = {
        kind: "ready",
        thought: decision.thought,
        ...(decision.thoughtOriginal ? { thoughtOriginal: decision.thoughtOriginal } : {}),
        results: results.map((item) => ({
          ...item,
          signature: signResult(ownerId, decision.thought, item.style, item.reframe, item.reframeOriginal),
        })),
        meta: decision.meta,
        model: answeredBy,
        signature: signCook({
          ownerId,
          thought: decision.thought,
          thoughtOriginal: decision.thoughtOriginal,
          model: answeredBy,
          meta: decision.meta,
        }),
      };
      return c.json(await finish(payload, "ready"));
    } catch (error) {
      if (
        error instanceof MeteringError &&
        error.code === "REQUEST_ALREADY_COMPLETED" &&
        replayKey
      ) {
        const replayed = await replayCompleted({
          ownerId,
          clientRequestId,
          requestFingerprint: fingerprint,
          replayKey,
        });
        if (replayed) {
          return c.json(replayed);
        }
      }
      if (operation) {
        try {
          await finishMeterOperation({
            operation,
            state: "failed",
            usageEvents,
          });
        } catch (cleanupError) {
          console.error("reframe_meter_cleanup_failed", {
            reason:
              cleanupError instanceof Error
                ? cleanupError.message
                : "unknown",
          });
        }
      }
      if (error instanceof MeteringError) {
        return c.json(meteringErrorResponse(error), error.status);
      }
      if (error instanceof DbError) {
        throw error;
      }
      const reason = error instanceof LlmError ? error.message : "unknown";
      console.error("reframe_failed", { followUpCount: followUps.length, reason });
      return c.json(errorBody("Failed to generate reframe", "LLM_ERROR"), 500);
    }
  },
);
