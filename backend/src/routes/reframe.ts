import { zValidator } from "@hono/zod-validator";
import { Hono } from "hono";
import { z } from "zod";
import { authStub } from "../lib/authStub.js";
import { errorBody } from "../lib/http.js";
import { generateReframe, LLM_MODEL_IDS, LlmError, type LlmModelId } from "../lib/llmClient.js";
import { SYSTEM_PROMPTS } from "../lib/prompts.js";
import {
  clarifyForFollowUps,
  composeLlmText,
  shouldReturnReady,
} from "../lib/refineDecision.js";
import {
  STYLES,
  type FollowUpAnswer,
  type ReadyResponse,
  type ReframeResponse,
  type Style,
} from "../types/index.js";

const MAX_TEXT_LENGTH = 2000;
const MAX_FOLLOW_UPS = 3;

const followUpSchema = z.object({
  question: z
    .string()
    .transform((value) => value.trim())
    .pipe(z.string().min(1, "question must not be empty").max(500)),
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
  followUps: z.array(followUpSchema).max(MAX_FOLLOW_UPS, "followUps must contain at most 3 entries").optional(),
  styles: z.array(styleSchema).min(1).max(STYLES.length).optional(),
  model: z.enum(LLM_MODEL_IDS).optional(),
});

function validationErrorMessage(error: { issues: { message: string }[] }): string {
  const first = error.issues[0];
  return first?.message ?? "Invalid request";
}

function uniqueStyles(styles: Style[]): Style[] {
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

async function generateStyles(
  text: string,
  styles: readonly Style[],
  model?: LlmModelId,
): Promise<ReadyResponse> {
  const requested = uniqueStyles([...styles]);
  const results = await Promise.all(
    requested.map(async (style: Style) => {
      const reframe = await generateReframe({
        text,
        systemPrompt: SYSTEM_PROMPTS[style],
        model,
      });
      const trimmed = reframe.trim();
      if (trimmed.length === 0) {
        throw new LlmError("LLM returned an empty reframe");
      }
      return { style, reframe: trimmed };
    }),
  );

  return { kind: "ready", results };
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
    const { text, followUps: rawFollowUps, styles, model } = c.req.valid("json");
    const followUps: FollowUpAnswer[] = rawFollowUps ?? [];

    try {
      let body: ReframeResponse;
      if (shouldReturnReady(text, followUps)) {
        body = await generateStyles(composeLlmText(text, followUps), styles ?? STYLES, model);
      } else {
        body = clarifyForFollowUps(followUps);
      }
      return c.json(body);
    } catch (error) {
      const reason = error instanceof LlmError ? error.message : "unknown";
      console.error("reframe_failed", { followUpCount: followUps.length, reason });
      return c.json(errorBody("Failed to generate reframe", "LLM_ERROR"), 500);
    }
  },
);
