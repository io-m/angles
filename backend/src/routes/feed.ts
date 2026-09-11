import { zValidator } from "@hono/zod-validator";
import { Hono } from "hono";
import { z } from "zod";
import { clearFeedSaves, listFeed, listHomeFeed, saveFeedAngle, unsaveFeedAngle } from "../db/feed.js";
import { authStub } from "../lib/authStub.js";
import { errorBody, validationErrorMessage } from "../lib/http.js";
import { CATEGORIES, EMOTIONS, STYLES } from "../types/index.js";

const listQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(500).optional().default(200),
  before: z
    .string()
    .refine((value) => !Number.isNaN(Date.parse(value)), "before must be an ISO-8601 timestamp")
    .optional(),
  category: z.enum(CATEGORIES).optional(),
  style: z.enum(STYLES).optional(),
  emotion: z.enum(EMOTIONS).optional(),
});

const homeQuerySchema = z.object({
  style: z.enum(STYLES).optional(),
  perSection: z.coerce.number().int().min(1).max(12).optional().default(6),
});

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
      before: query.before ? new Date(query.before) : undefined,
      category: query.category,
      style: query.style,
      emotion: query.emotion,
    });
    return c.json({ cards: cardList });
  },
);

feedRoute.get(
  "/home",
  authStub,
  zValidator("query", homeQuerySchema, (result, c) => {
    if (!result.success) {
      return c.json(errorBody(validationErrorMessage(result.error), "VALIDATION_ERROR"), 400);
    }
  }),
  async (c) => {
    const query = c.req.valid("query");
    const home = await listHomeFeed({
      style: query.style,
      perSection: query.perSection,
    });
    return c.json(home);
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
