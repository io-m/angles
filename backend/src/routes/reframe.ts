import { zValidator } from "@hono/zod-validator";
import { Hono } from "hono";
import { z } from "zod";
import { authStub } from "../lib/authStub.js";
import { runDecision, type ReadyDecision } from "../lib/decision.js";
import { errorBody } from "../lib/http.js";
import { generateReframe, LLM_MODEL_IDS, LlmError, type LlmModelId } from "../lib/llmClient.js";
import {
  REFRAME_HARD_MAX_CHARS,
  REFRAME_TOO_LONG_RETRY,
  SYSTEM_PROMPTS,
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

function validationErrorMessage(error: { issues: { message: string }[] }): string {
  const first = error.issues[0];
  return first?.message ?? "Invalid request";
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

async function generateStyle(
  decision: ReadyDecision,
  style: Style,
  model?: LlmModelId,
): Promise<ReframeResult> {
  const prompt = styleUserPrompt(decision.thought, decision.meta);
  const first = (await generateReframe({ text: prompt, systemPrompt: SYSTEM_PROMPTS[style], model }))
    .trim();
  if (first.length === 0) {
    throw new LlmError("LLM returned an empty reframe");
  }
  if (first.length <= REFRAME_HARD_MAX_CHARS) {
    return { style, reframe: first };
  }

  const retried = (
    await generateReframe({
      text: prompt,
      systemPrompt: `${SYSTEM_PROMPTS[style]}\n\n${REFRAME_TOO_LONG_RETRY}`,
      model,
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

    try {
      const decision = await runDecision({
        text,
        followUps,
        model,
        forceReady: followUps.length >= FORCE_READY_AFTER,
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

      const results = await Promise.all(
        chosen.map((style) => generateStyle(decision, style, model)),
      );

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
