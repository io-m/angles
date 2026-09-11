import { zValidator } from "@hono/zod-validator";
import { Hono } from "hono";
import { z } from "zod";
import { clearFeedSaves, listFeed, saveFeedAngle, unsaveFeedAngle } from "../db/feed.js";
import { authStub } from "../lib/authStub.js";
import { errorBody, validationErrorMessage } from "../lib/http.js";
import { CATEGORIES, EMOTIONS, STYLES, type FeedCursor } from "../types/index.js";

function enumCsvSchema<const T extends readonly [string, ...string[]]>(values: T) {
  const allowed = new Set<string>(values);
  return z.string().transform((raw, context): T[number][] => {
    const tokens = raw.split(",").map((token) => token.trim());
    if (tokens.some((token) => token.length === 0 || !allowed.has(token))) {
      context.addIssue({
        code: "custom",
        message: `must be a comma-separated list containing only: ${values.join(", ")}`,
      });
      return z.NEVER;
    }

    const selected = new Set(tokens);
    return values.filter((value) => selected.has(value));
  });
}

function feedCursorSchema() {
  return z.string().transform((raw, context): FeedCursor => {
    const parts = raw.split("|");
    const createdAt = parts[0] ? new Date(parts[0]) : new Date(Number.NaN);
    const id = parts[1];
    if (
      parts.length !== 2 ||
      Number.isNaN(createdAt.getTime()) ||
      !id ||
      !z.uuid().safeParse(id).success
    ) {
      context.addIssue({
        code: "custom",
        message: "before must be an ISO-8601 timestamp and UUID separated by |",
      });
      return z.NEVER;
    }
    return { createdAt, id };
  });
}

const listQuerySchema = z
  .object({
    limit: z.coerce.number().int().min(1).max(500).optional().default(200),
    before: feedCursorSchema().optional(),
    categories: enumCsvSchema(CATEGORIES).optional(),
    emotions: enumCsvSchema(EMOTIONS).optional(),
  })
  .strict();

const idParamSchema = z.object({
  id: z.uuid(),
});

const angleParamSchema = z.object({
  id: z.uuid(),
  style: z.enum(STYLES),
});

export const feedRoute = new Hono();

feedRoute.get(
  "/",
  authStub,
  zValidator("query", listQuerySchema, (result, c) => {
    if (!result.success) {
      return c.json(errorBody(validationErrorMessage(result.error), "VALIDATION_ERROR"), 400);
    }
  }),
  async (c) => {
    const query = c.req.valid("query");
    const cardList = await listFeed({
      limit: query.limit,
      before: query.before,
      categories: query.categories,
      emotions: query.emotions,
    });
    return c.json({ cards: cardList });
  },
);

feedRoute.put(
  "/cards/:id/angles/:style",
  authStub,
  zValidator("param", angleParamSchema, (result, c) => {
    if (!result.success) {
      return c.json(errorBody(validationErrorMessage(result.error), "VALIDATION_ERROR"), 400);
    }
  }),
  async (c) => {
    const { id, style } = c.req.valid("param");
    const result = await saveFeedAngle(id, style);
    if (!result.ok) {
      if (result.reason === "unknown_style") {
        return c.json(errorBody("style must be one of the card results", "VALIDATION_ERROR"), 400);
      }
      return c.json(errorBody("Not found", "NOT_FOUND"), 404);
    }
    return c.json(result.card);
  },
);

feedRoute.delete(
  "/cards/:id/angles/:style",
  authStub,
  zValidator("param", angleParamSchema, (result, c) => {
    if (!result.success) {
      return c.json(errorBody(validationErrorMessage(result.error), "VALIDATION_ERROR"), 400);
    }
  }),
  async (c) => {
    const { id, style } = c.req.valid("param");
    const result = await unsaveFeedAngle(id, style);
    if (!result.ok) {
      if (result.reason === "unknown_style") {
        return c.json(errorBody("style must be one of the card results", "VALIDATION_ERROR"), 400);
      }
      return c.json(errorBody("Not found", "NOT_FOUND"), 404);
    }
    return c.json(result.card);
  },
);

feedRoute.delete(
  "/cards/:id/saves",
  authStub,
  zValidator("param", idParamSchema, (result, c) => {
    if (!result.success) {
      return c.json(errorBody(validationErrorMessage(result.error), "VALIDATION_ERROR"), 400);
    }
  }),
  async (c) => {
    const { id } = c.req.valid("param");
    const result = await clearFeedSaves(id);
    if (!result.ok) {
      return c.json(errorBody("Not found", "NOT_FOUND"), 404);
    }
    return c.body(null, 204);
  },
);
