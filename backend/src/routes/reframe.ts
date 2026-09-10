import { zValidator } from "@hono/zod-validator";
import { Hono } from "hono";
import { z } from "zod";
import { authStub } from "../lib/authStub.js";
import { runDecision, type ReadyDecision } from "../lib/decision.js";
import { errorBody, validationErrorMessage } from "../lib/http.js";
import {
  COOK_DEADLINE_MS,
  generateJson,
  generateReframe,
  LLM_MODEL_IDS,
  LlmError,
  STYLE_BATCH_MAX_OUTPUT_TOKENS,
  timeoutMsUntil,
  type LlmCallOptions,
  type LlmModelId,
} from "../lib/llmClient.js";
import {
  REFRAME_HARD_MAX_CHARS,
  REFRAME_TOO_LONG_RETRY,
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
});

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
      ...callOptions(options),
    })
  ).trim();
  if (first.length === 0) {
    throw new LlmError("LLM returned an empty reframe");
  }
  if (first.length <= REFRAME_HARD_MAX_CHARS) {
    return { style, reframe: first };
  }

  return finishLongReframe(prompt, style, options);
}

async function finishLongReframe(
  prompt: string,
  style: Style,
  options: CookCallOptions,
): Promise<ReframeResult> {
  const retried = (
    await generateReframe({
      text: prompt,
      systemPrompt: `${SYSTEM_PROMPTS[style]}\n\n${REFRAME_TOO_LONG_RETRY}`,
      ...callOptions(options),
    })
  ).trim();
  if (retried.length === 0) {
    throw new LlmError("LLM returned an empty reframe");
  }

  return {
    style,
    reframe: retried.length <= REFRAME_HARD_MAX_CHARS ? retried : trimToSentence(retried),
  };
}

async function requestStyleBatch(
  decision: ReadyDecision,
  chosen: Style[],
  options: CookCallOptions,
): Promise<string> {
  return generateJson({
    text: styleBatchUserPrompt(decision.thought, decision.meta, chosen),
    systemPrompt: STYLE_BATCH_PROMPT,
    maxOutputTokens: STYLE_BATCH_MAX_OUTPUT_TOKENS,
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
    raw = await requestStyleBatch(decision, chosen, options);
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
      const retried = await requestStyleBatch(decision, chosen, options);
      parsed = parseStyleBatch(retried, chosen);
    } catch {
      throw new LlmError("Style batch reply could not be parsed");
    }
  }

  const results: ReframeResult[] = [];
  const prompt = styleUserPrompt(decision.thought, decision.meta);

  for (const style of chosen) {
    const fromBatch = parsed[style];
    if (fromBatch === undefined) {
      results.push(await generateStyle(decision, style, options));
      continue;
    }
    if (fromBatch.length <= REFRAME_HARD_MAX_CHARS) {
      results.push({ style, reframe: fromBatch });
      continue;
    }
    results.push(await finishLongReframe(prompt, style, options));
  }

  return results;
}

/** A style the decision refused is answered with its reason, never with a bad joke. */
function refusedStyleResponse(decision: ReadyDecision, style: Style): ContinueResponse {
  const skipped = decision.meta.skippedStyles.find((item) => item.style === style);
  return {
    kind: "continue",
    message: skipped?.reason ?? "That angle would not land well on this one.",
    options: [],
    safety: decision.meta.safety,
  };
}

export const reframeRoute = new Hono();

reframeRoute.post(
  "/",
  authStub,
  zValidator("json", reframeRequestSchema, (result, c) => {
    if (!result.success) {
      return c.json(errorBody(validationErrorMessage(result.error), "VALIDATION_ERROR"), 400);
    }
  }),
  async (c) => {
    const { text, followUps: rawFollowUps, styles: requestedStyles, model } = c.req.valid("json");
    const followUps: FollowUpAnswer[] = rawFollowUps ?? [];
    const deadlineAt = Date.now() + COOK_DEADLINE_MS;
    const abortSignal = c.req.raw.signal;

    try {
      const decision = await runDecision({
        text,
        followUps,
        model,
        forceReady: followUps.length >= FORCE_READY_AFTER,
        deadlineAt,
        abortSignal,
      });

      if (decision.kind === "continue") {
        const body: ReframeResponse = {
          kind: "continue",
          message: decision.message,
          options: decision.options,
          safety: decision.safety,
        };
        return c.json(body);
      }

      const chosen = requestedStyles
        ? uniqueStyles(requestedStyles).filter((style) => decision.styles.includes(style))
        : uniqueStyles(decision.styles);

      if (chosen.length === 0) {
        const refused = requestedStyles?.[0];
        return c.json(
          refused
            ? refusedStyleResponse(decision, refused)
            : ({
                kind: "continue",
                message: "I could not find an angle worth putting on a card yet.",
                options: [],
                safety: decision.meta.safety,
              } satisfies ContinueResponse),
        );
      }

      const options: CookCallOptions = { deadlineAt, abortSignal, model };
      const recookStyle = requestedStyles !== undefined && chosen.length === 1 ? chosen[0] : undefined;
      const results = recookStyle
        ? [await generateStyle(decision, recookStyle, options)]
        : await generateStyleBatch(decision, chosen, options);

      const body: ReframeResponse = {
        kind: "ready",
        thought: decision.thought,
        ...(decision.thoughtOriginal ? { thoughtOriginal: decision.thoughtOriginal } : {}),
        results,
        meta: decision.meta,
      };
      return c.json(body);
    } catch (error) {
      const reason = error instanceof LlmError ? error.message : "unknown";
      console.error("reframe_failed", { followUpCount: followUps.length, reason });
      return c.json(errorBody("Failed to generate reframe", "LLM_ERROR"), 500);
    }
  },
);
