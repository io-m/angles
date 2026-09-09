import { zValidator } from "@hono/zod-validator";
import { Hono } from "hono";
import { z } from "zod";
import { authStub } from "../lib/authStub.js";
import { errorBody } from "../lib/http.js";
import { generateReframe, LlmError } from "../lib/llmClient.js";
import { SYSTEM_PROMPTS } from "../lib/prompts.js";
import { STYLES, type ReframeResponse, type Style } from "../types/index.js";

const MAX_TEXT_LENGTH = 2000;

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
  styles: z
    .array(z.enum(STYLES))
    .min(1, "styles must contain at least one style")
    .max(STYLES.length, "styles contains too many entries")
    .refine((items) => new Set(items).size === items.length, {
      message: "styles must not contain duplicates",
    }),
});

function validationErrorMessage(error: { issues: { message: string }[] }): string {
  const first = error.issues[0];
  return first?.message ?? "Invalid request";
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
    const { text, styles } = c.req.valid("json");

    try {
      const results = await Promise.all(
        styles.map(async (style: Style) => {
          const reframe = await generateReframe({
            text,
            systemPrompt: SYSTEM_PROMPTS[style],
          });
          const trimmed = reframe.trim();
          if (trimmed.length === 0) {
            throw new LlmError("LLM returned an empty reframe");
          }
          return { style, reframe: trimmed };
        }),
      );

      const body: ReframeResponse = { results };
      return c.json(body);
    } catch (error) {
      const reason = error instanceof LlmError ? error.message : "unknown";
      console.error("reframe_failed", { styleCount: styles.length, reason });
      return c.json(errorBody("Failed to generate reframe", "LLM_ERROR"), 500);
    }
  },
);
