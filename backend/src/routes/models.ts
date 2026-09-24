import { zValidator } from "@hono/zod-validator";
import { Hono } from "hono";
import { z } from "zod";
import { listPublicCardsForModel } from "../db/feed.js";
import { errorBody, validationErrorMessage } from "../lib/http.js";
import { cardCursorSchema } from "../lib/cursor.js";
import { LLM_MODEL_IDS } from "../lib/llmClient.js";
import { authStub } from "../lib/authStub.js";
import type { ModelCardsResponse } from "../types/index.js";

const paramsSchema = z.object({
  id: z.enum(LLM_MODEL_IDS),
});

const querySchema = z
  .object({
    limit: z.coerce.number().int().min(1).max(500).optional().default(24),
    before: cardCursorSchema().optional(),
  })
  .strict();

export const modelsRoute = new Hono();

modelsRoute.get(
  "/:id/cards",
  authStub,
  zValidator("param", paramsSchema, (result, c) => {
    if (!result.success) {
      return c.json(errorBody(validationErrorMessage(result.error), "VALIDATION_ERROR"), 400);
    }
  }),
  zValidator("query", querySchema, (result, c) => {
    if (!result.success) {
      return c.json(errorBody(validationErrorMessage(result.error), "VALIDATION_ERROR"), 400);
    }
  }),
  async (c) => {
    const { id } = c.req.valid("param");
    const query = c.req.valid("query");
    const cards = await listPublicCardsForModel({
      model: id,
      limit: query.limit,
      before: query.before,
    });
    const body: ModelCardsResponse = { model: id, cards };
    return c.json(body);
  },
);
