import { randomUUID } from "node:crypto";
import { zValidator } from "@hono/zod-validator";
import { Hono } from "hono";
import { z } from "zod";
import { DbError } from "../db/client.js";
import {
  beginProviderCall,
  finishMeterOperation,
  MeteringError,
  startMeterOperation,
  type StartedMeterOperation,
} from "../db/metering.js";
import { getOwnerUserId, requireAuth } from "../lib/authStub.js";
import { signCook, signResult } from "../lib/cookSignature.js";
import { runDecision, type ReadyDecision } from "../lib/decision.js";
import { errorBody, validationErrorMessage } from "../lib/http.js";
import {
  COOK_DEADLINE_MS,
  generateJson,
  generateReframe,
  LLM_MODEL_IDS,
  LlmError,
  resolveEffectiveModel,
  STYLE_BATCH_MAX_OUTPUT_TOKENS,
  timeoutMsUntil,
  type LlmCallOptions,
  type LlmModelId,
} from "../lib/llmClient.js";
import type { LlmUsageEvent } from "../lib/llmUsage.js";
import {
  MODEL_CREDIT_COST,
  isPublicLlmModel,
  isUsageEnforcementRequired,
  requestFingerprint,
  type UsageSummary,
} from "../lib/meteringPolicy.js";
import {
  REFRAME_HARD_MAX_CHARS,
  STYLE_BATCH_PROMPT,
  SYSTEM_PROMPTS,
  styleBatchUserPrompt,
  styleUserPrompt,
} from "../lib/prompts.js";
import {
  STYLES,
  type ContinueResponse,
  type FollowUpAnswer,
  type ReframeResponse,
  type ReframeResult,
  type Style,
} from "../types/index.js";

const MAX_TEXT_LENGTH = 2000;
/** The model drives the exchange; this is an abuse guard, not a script length. */
const MAX_FOLLOW_UPS = 6;
/** From here on the decision call is told to land it, safety aside. */
const FORCE_READY_AFTER = 3;

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

const styleSchema = z.enum(STYLES);

const reframeRequestSchema = z.object({
  text: z
    .string()
    .transform((value) => value.trim())
    .pipe(
      z
        .string()
        .min(1, "text must not be empty")
        .max(MAX_TEXT_LENGTH, `text must be at most ${MAX_TEXT_LENGTH} characters`),
    ),
  followUps: z
    .array(followUpSchema)
    .max(MAX_FOLLOW_UPS, `followUps must contain at most ${MAX_FOLLOW_UPS} entries`)
    .optional(),
  styles: z.array(styleSchema).min(1).max(STYLES.length).optional(),
  model: z.enum(LLM_MODEL_IDS).optional(),
}).strict();

type CookCallOptions = LlmCallOptions & {
  deadlineAt: number;
  model?: LlmModelId;
};

class StyleBatchParseError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "StyleBatchParseError";
  }
}

function uniqueStyles(styles: readonly Style[]): Style[] {
  const seen = new Set<Style>();
  const unique: Style[] = [];
  for (const style of styles) {
    if (!seen.has(style)) {
      seen.add(style);
      unique.push(style);
    }
  }
  return unique;
}

function trimToSentence(reframe: string): string {
  const clipped = reframe.slice(0, REFRAME_HARD_MAX_CHARS);
  const lastStop = Math.max(
    clipped.lastIndexOf("."),
    clipped.lastIndexOf("!"),
    clipped.lastIndexOf("?"),
  );
  if (lastStop > REFRAME_HARD_MAX_CHARS / 2) {
    return clipped.slice(0, lastStop + 1).trim();
  }
  return `${clipped.trim().replace(/[,;:\s]+$/, "")}…`;
}

function callOptions(options: CookCallOptions): LlmCallOptions & { model?: LlmModelId } {
  return {
    model: options.model,
    abortSignal: options.abortSignal,
    timeoutMs: timeoutMsUntil(options.deadlineAt),
    beforeProviderCall: options.beforeProviderCall,
    usageSink: options.usageSink,
  };
}

function extractJsonObject(raw: string): string {
  const withoutFence = raw.replace(/```[a-zA-Z]*\s*/g, "").replace(/```/g, "").trim();
  const start = withoutFence.indexOf("{");
  const end = withoutFence.lastIndexOf("}");
  if (start === -1 || end <= start) {
    throw new StyleBatchParseError("style batch reply was not JSON");
  }
  return withoutFence.slice(start, end + 1);
}

function parseStyleBatch(raw: string, chosen: readonly Style[]): Partial<Record<Style, string>> {
  let parsed: unknown;
  try {
    parsed = JSON.parse(extractJsonObject(raw));
  } catch (error) {
    if (error instanceof StyleBatchParseError) {
      throw error;
    }
    throw new StyleBatchParseError("style batch reply was not JSON");
  }

  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new StyleBatchParseError("style batch reply was not an object");
  }

  const record = parsed as Record<string, unknown>;
  const out: Partial<Record<Style, string>> = {};
  for (const style of chosen) {
    const value = record[style];
    if (typeof value === "string") {
      const trimmed = value.trim();
      if (trimmed.length > 0) {
        out[style] = trimmed;
      }
    }
  }
  if (Object.keys(out).length !== chosen.length) {
    throw new StyleBatchParseError("style batch reply omitted a requested style");
  }
  return out;
}

async function generateStyle(
  decision: ReadyDecision,
  style: Style,
  options: CookCallOptions,
): Promise<ReframeResult> {
  const prompt = styleUserPrompt(decision.thought, decision.meta);
  const first = (
    await generateReframe({
      text: prompt,
      systemPrompt: SYSTEM_PROMPTS[style],
      callKind: "reframe",
      attempt: 1,
      ...callOptions(options),
    })
  ).trim();
  if (first.length === 0) {
    throw new LlmError("LLM returned an empty reframe");
  }
  if (first.length <= REFRAME_HARD_MAX_CHARS) {
    return { style, reframe: first };
  }
  return {
    style,
    reframe: trimToSentence(first),
  };
}

async function requestStyleBatch(
  decision: ReadyDecision,
  chosen: Style[],
  options: CookCallOptions,
  attempt: number,
): Promise<string> {
  return generateJson({
    text: styleBatchUserPrompt(decision.thought, decision.meta, chosen),
    systemPrompt: STYLE_BATCH_PROMPT,
    maxOutputTokens: STYLE_BATCH_MAX_OUTPUT_TOKENS,
    callKind: "batch",
    attempt,
    ...callOptions(options),
  });
}

async function generateStyleBatch(
  decision: ReadyDecision,
  chosen: Style[],
  options: CookCallOptions,
): Promise<ReframeResult[]> {
  let raw: string;
  try {
    raw = await requestStyleBatch(decision, chosen, options, 1);
  } catch (error) {
    if (error instanceof LlmError) {
      throw error;
    }
    throw new LlmError("Style batch failed", { cause: error });
  }

  let parsed: Partial<Record<Style, string>>;
  try {
    parsed = parseStyleBatch(raw, chosen);
  } catch (error) {
    if (!(error instanceof StyleBatchParseError)) {
      throw error;
    }
    try {
      const retried = await requestStyleBatch(decision, chosen, options, 2);
      parsed = parseStyleBatch(retried, chosen);
    } catch {
      throw new LlmError("Style batch reply could not be parsed");
    }
  }

  const results: ReframeResult[] = [];
  for (const style of chosen) {
    const fromBatch = parsed[style];
    if (fromBatch === undefined) {
      throw new LlmError("Style batch reply omitted a requested style");
    }
    if (fromBatch.length <= REFRAME_HARD_MAX_CHARS) {
      results.push({ style, reframe: fromBatch });
      continue;
    }
    results.push({ style, reframe: trimToSentence(fromBatch) });
  }

  return results;
}

/** A style the decision refused is answered with its reason, never with a bad joke. */
function refusedStyleResponse(
  decision: ReadyDecision,
  style: Style,
): Omit<ContinueResponse, "usage"> {
  const skipped = decision.meta.skippedStyles.find((item) => item.style === style);
  return {
    kind: "continue",
    message: skipped?.reason ?? "That angle would not land well on this one.",
    options: [],
    safety: decision.meta.safety,
  };
}

export const reframeRoute = new Hono();

function responseUsage(
  summary: UsageSummary,
  creditsUsed: number,
  model: LlmModelId,
): {
  creditsUsed: number;
  remaining: number;
  granted: number;
  resetsAt: string | null;
  warning: UsageSummary["warning"];
  allowedModels: UsageSummary["allowedModels"];
  creditCost: number;
} {
  return {
    creditsUsed,
    remaining: summary.creditsRemaining,
    granted: summary.creditsGranted,
    resetsAt: summary.resetsAt,
    warning: summary.warning,
    allowedModels: summary.allowedModels,
    creditCost: isPublicLlmModel(model) ? MODEL_CREDIT_COST[model] : 0,
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
          allowedModels: error.usage.allowedModels,
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
    const { text, followUps: rawFollowUps, styles: requestedStyles } = validated;
    const followUps: FollowUpAnswer[] = rawFollowUps ?? [];
    const deadlineAt = Date.now() + COOK_DEADLINE_MS;
    const abortSignal = c.req.raw.signal;
    const ownerId = getOwnerUserId();
    let model: LlmModelId;
    try {
      model = resolveEffectiveModel(validated.model);
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
    const fingerprint = requestFingerprint(validated, model);
    const usageEvents: LlmUsageEvent[] = [];
    let operation: StartedMeterOperation | undefined;

    try {
      const startedOperation = await startMeterOperation({
        ownerId,
        clientRequestId,
        requestFingerprint: fingerprint,
        model,
        kind: requestedStyles === undefined ? "full" : "recook",
      });
      operation = startedOperation;
      const meteredCallOptions = {
        beforeProviderCall: () => beginProviderCall(startedOperation),
        usageSink: (event: LlmUsageEvent) => usageEvents.push(event),
      };
      const decision = await runDecision({
        text,
        followUps,
        model,
        forceReady: followUps.length >= FORCE_READY_AFTER,
        deadlineAt,
        abortSignal,
        ...meteredCallOptions,
      });

      if (decision.kind === "continue") {
        const summary = await finishMeterOperation({
          operation,
          state: "continue",
          resultKind: "continue",
          usageEvents,
        });
        const body: ReframeResponse = {
          kind: "continue",
          message: decision.message,
          options: decision.options,
          safety: decision.safety,
          usage: responseUsage(summary, 0, model),
        };
        return c.json(body);
      }

      const chosen = requestedStyles
        ? uniqueStyles(requestedStyles).filter((style) => decision.styles.includes(style))
        : uniqueStyles(decision.styles);

      if (chosen.length === 0) {
        const refused = requestedStyles?.[0];
        const summary = await finishMeterOperation({
          operation,
          state: "continue",
          resultKind: "continue",
          usageEvents,
        });
        const response = refused
          ? refusedStyleResponse(decision, refused)
          : ({
              kind: "continue",
              message: "I could not find an angle worth putting on a card yet.",
              options: [],
              safety: decision.meta.safety,
            } satisfies Omit<ContinueResponse, "usage">);
        return c.json(
          { ...response, usage: responseUsage(summary, 0, model) },
        );
      }

      const options: CookCallOptions = {
        deadlineAt,
        abortSignal,
        model,
        ...meteredCallOptions,
      };
      const recookStyle = requestedStyles !== undefined && chosen.length === 1 ? chosen[0] : undefined;
      const results = recookStyle
        ? [await generateStyle(decision, recookStyle, options)]
        : await generateStyleBatch(decision, chosen, options);

      // A recook keeps the card's thought and meta, and the client sends that thought as `text`.
      const signedThought = recookStyle ? text : decision.thought;
      const summary = await finishMeterOperation({
        operation,
        state: "ready",
        resultKind: "ready",
        usageEvents,
      });
      const creditsUsed =
        operation.taste || !isPublicLlmModel(model) ? 0 : MODEL_CREDIT_COST[model];
      const body: ReframeResponse = {
        kind: "ready",
        thought: decision.thought,
        ...(decision.thoughtOriginal ? { thoughtOriginal: decision.thoughtOriginal } : {}),
        results: results.map((item) => ({
          ...item,
          signature: signResult(signedThought, item.style, item.reframe, model),
        })),
        meta: decision.meta,
        signature: signCook({
          thought: decision.thought,
          thoughtOriginal: decision.thoughtOriginal,
          model,
          meta: decision.meta,
        }),
        usage: responseUsage(summary, creditsUsed, model),
      };
      return c.json(body);
    } catch (error) {
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
