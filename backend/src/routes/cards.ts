import { zValidator } from "@hono/zod-validator";
import { Hono } from "hono";
import { z } from "zod";
import { createCard, deleteCard, getCard, listCards, patchCard } from "../db/cards.js";
import { authStub } from "../lib/authStub.js";
import { errorBody, validationErrorMessage } from "../lib/http.js";
import { LLM_MODEL_IDS } from "../lib/llmClient.js";
import {
  CATEGORIES,
  EMOTIONS,
  SAFETY_FLAGS,
  STYLES,
  TIMEFRAMES,
} from "../types/index.js";

const MAX_THOUGHT_LENGTH = 2000;
const MAX_REFRAME_LENGTH = 4000;

const skippedStyleSchema = z.object({
  style: z.enum(STYLES),
  reason: z.string().min(1).max(400),
});

const createMetaSchema = z
  .object({
    category: z.enum(CATEGORIES),
    proposedCategory: z.string().min(1).max(64).optional(),
    proposedLabel: z.string().min(1).max(64).optional(),
    tags: z.array(z.string().max(48)).max(8).default([]),
    intensity: z.number().int().min(1).max(5),
    timeframe: z.enum(TIMEFRAMES),
    emotions: z.array(z.enum(EMOTIONS)).max(3),
    safety: z.enum(SAFETY_FLAGS),
    inputLanguage: z.string().min(1).max(32),
    skippedStyles: z.array(skippedStyleSchema).default([]),
    matching: z.unknown().optional(),
  })
  .transform(({ matching: _matching, ...rest }) => rest);

const createCardSchema = z
  .object({
    thought: z
      .string()
      .transform((value) => value.trim())
      .pipe(z.string().min(1, "thought must not be empty").max(MAX_THOUGHT_LENGTH)),
    thoughtOriginal: z
      .string()
      .transform((value) => value.trim())
      .pipe(z.string().min(1).max(MAX_THOUGHT_LENGTH))
      .optional(),
    results: z
      .array(
        z.object({
          style: z.enum(STYLES),
          reframe: z
            .string()
            .transform((value) => value.trim())
            .pipe(z.string().min(1, "reframe must not be empty").max(MAX_REFRAME_LENGTH)),
        }),
      )
      .min(1)
      .max(STYLES.length)
      .refine((items) => new Set(items.map((item) => item.style)).size === items.length, {
        message: "results must not repeat a style",
      }),
    meta: createMetaSchema,
    model: z.enum(LLM_MODEL_IDS),
    spotlightStyle: z.enum(STYLES),
  })
  .refine((body) => body.results.some((item) => item.style === body.spotlightStyle), {
    message: "spotlightStyle must be one of the results",
  });

const listQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).optional().default(50),
  before: z
    .string()
    .refine((value) => !Number.isNaN(Date.parse(value)), "before must be an ISO-8601 timestamp")
    .optional(),
  category: z.enum(CATEGORIES).optional(),
  style: z.enum(STYLES).optional(),
  favorite: z
    .enum(["true", "false"])
    .optional()
    .transform((value) => (value === undefined ? undefined : value === "true")),
  pinned: z
    .enum(["true", "false"])
    .optional()
    .transform((value) => (value === undefined ? undefined : value === "true")),
});

const idParamSchema = z.object({
  id: z.uuid(),
});

const patchCardSchema = z
  .object({
    isFavorite: z.boolean().optional(),
    style: z.enum(STYLES).optional(),
    isPinned: z.boolean().optional(),
    isPublic: z.boolean().optional(),
  })
  .refine(
    (body) =>
      body.isFavorite !== undefined || body.isPinned !== undefined || body.isPublic !== undefined,
    { message: "patch must set isFavorite, isPinned, or isPublic" },
  )
  .refine((body) => body.isFavorite === undefined || body.style !== undefined, {
    message: "style is required when setting isFavorite",
  });

export const cardsRoute = new Hono();

cardsRoute.post(
  "/",
  authStub,
  zValidator("json", createCardSchema, (result, c) => {
    if (!result.success) {
      return c.json(errorBody(validationErrorMessage(result.error), "VALIDATION_ERROR"), 400);
    }
  }),
  async (c) => {
    const body = c.req.valid("json");
    const card = await createCard(body);
    return c.json(card, 201);
  },
);

cardsRoute.get(
  "/",
  authStub,
  zValidator("query", listQuerySchema, (result, c) => {
    if (!result.success) {
      return c.json(errorBody(validationErrorMessage(result.error), "VALIDATION_ERROR"), 400);
    }
  }),
  async (c) => {
    const query = c.req.valid("query");
    const cardList = await listCards({
      limit: query.limit,
      before: query.before ? new Date(query.before) : undefined,
      category: query.category,
      style: query.style,
      favorite: query.favorite,
      pinned: query.pinned,
    });
    return c.json({ cards: cardList });
  },
);

cardsRoute.get(
  "/:id",
  authStub,
  zValidator("param", idParamSchema, (result, c) => {
    if (!result.success) {
      return c.json(errorBody(validationErrorMessage(result.error), "VALIDATION_ERROR"), 400);
    }
  }),
  async (c) => {
    const { id } = c.req.valid("param");
    const card = await getCard(id);
    if (!card) {
      return c.json(errorBody("Not found", "NOT_FOUND"), 404);
    }
    return c.json(card);
  },
);

cardsRoute.patch(
  "/:id",
  authStub,
  zValidator("param", idParamSchema, (result, c) => {
    if (!result.success) {
      return c.json(errorBody(validationErrorMessage(result.error), "VALIDATION_ERROR"), 400);
    }
  }),
  zValidator("json", patchCardSchema, (result, c) => {
    if (!result.success) {
      return c.json(errorBody(validationErrorMessage(result.error), "VALIDATION_ERROR"), 400);
    }
  }),
  async (c) => {
    const { id } = c.req.valid("param");
    const patch = c.req.valid("json");
    const result = await patchCard(id, patch);
    if (!result.ok) {
      if (result.reason === "not_found") {
        return c.json(errorBody("Not found", "NOT_FOUND"), 404);
      }
      return c.json(errorBody("style must be one of the card results", "VALIDATION_ERROR"), 400);
    }
    return c.json(result.card);
  },
);

cardsRoute.delete(
  "/:id",
  authStub,
  zValidator("param", idParamSchema, (result, c) => {
    if (!result.success) {
      return c.json(errorBody(validationErrorMessage(result.error), "VALIDATION_ERROR"), 400);
    }
  }),
  async (c) => {
    const { id } = c.req.valid("param");
    const deleted = await deleteCard(id);
    if (!deleted) {
      return c.json(errorBody("Not found", "NOT_FOUND"), 404);
    }
    return c.body(null, 204);
  },
);
