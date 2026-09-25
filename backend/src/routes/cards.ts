import { zValidator } from "@hono/zod-validator";
import { Hono } from "hono";
import { z } from "zod";
import { reportCard } from "../db/communitySafety.js";
import {
  createCard,
  deleteCard,
  getCard,
  hasPublicationReportLock,
  listCards,
  patchCard,
} from "../db/cards.js";
import { requireAuth } from "../lib/authStub.js";
import { verifyCook } from "../lib/cookSignature.js";
import { cardCursorSchema } from "../lib/cursor.js";
import { errorBody, validationErrorMessage } from "../lib/http.js";
import { LLM_MODEL_IDS } from "../lib/llmClient.js";
import { REPORT_REASONS } from "../lib/communitySafetyTypes.js";
import { moderatePublicCard } from "../lib/publicModeration.js";
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
          signature: z.string().min(1).max(128),
        }),
      )
      .min(1)
      .max(STYLES.length)
      .refine((items) => new Set(items.map((item) => item.style)).size === items.length, {
        message: "results must not repeat a style",
      }),
    meta: createMetaSchema,
    signature: z.string().min(1).max(128),
    model: z.enum(LLM_MODEL_IDS),
    spotlightStyle: z.enum(STYLES),
    isPublic: z.boolean().optional(),
  })
  .refine((body) => body.results.some((item) => item.style === body.spotlightStyle), {
    message: "spotlightStyle must be one of the results",
  });

const listQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(500).optional().default(50),
  before: cardCursorSchema().optional(),
  category: z.enum(CATEGORIES).optional(),
  style: z.enum(STYLES).optional(),
  favorite: z
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
    isPublic: z.boolean().optional(),
  })
  .refine((body) => body.isFavorite !== undefined || body.isPublic !== undefined, {
    message: "patch must set isFavorite or isPublic",
  })
  .refine((body) => body.isFavorite === undefined || body.style !== undefined, {
    message: "style is required when setting isFavorite",
  });

const reportCardSchema = z
  .object({
    reason: z.enum(REPORT_REASONS),
  })
  .strict();

export const cardsRoute = new Hono();

cardsRoute.post(
  "/",
  requireAuth,
  zValidator("json", createCardSchema, (result, c) => {
    if (!result.success) {
      return c.json(errorBody(validationErrorMessage(result.error), "VALIDATION_ERROR"), 400);
    }
  }),
  async (c) => {
    const { signature, results, ...rest } = c.req.valid("json");
    if (rest.meta.safety !== "none" || !verifyCook({ ...rest, signature, results })) {
      return c.json(errorBody("card does not match a reframe from this server", "VALIDATION_ERROR"), 400);
    }
    if (rest.isPublic === true) {
      let allowed: boolean;
      try {
        allowed = await moderatePublicCard({
          thought: rest.thought,
          reframes: results.map((result) => result.reframe),
        });
      } catch {
        return c.json(
          errorBody("Public content moderation is unavailable", "PUBLIC_MODERATION_UNAVAILABLE"),
          503,
        );
      }
      if (!allowed) {
        return c.json(
          errorBody("This card cannot be published", "PUBLIC_CONTENT_NOT_ALLOWED"),
          400,
        );
      }
    }
    const card = await createCard({
      ...rest,
      results: results.map(({ style, reframe }) => ({ style, reframe })),
    });
    return c.json(card, 201);
  },
);

cardsRoute.get(
  "/",
  requireAuth,
  zValidator("query", listQuerySchema, (result, c) => {
    if (!result.success) {
      return c.json(errorBody(validationErrorMessage(result.error), "VALIDATION_ERROR"), 400);
    }
  }),
  async (c) => {
    const query = c.req.valid("query");
    const cardList = await listCards({
      limit: query.limit,
      before: query.before,
      category: query.category,
      style: query.style,
      favorite: query.favorite,
    });
    return c.json({ cards: cardList });
  },
);

cardsRoute.get(
  "/:id",
  requireAuth,
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
  requireAuth,
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
    if (patch.isPublic === true) {
      const card = await getCard(id);
      if (!card) {
        return c.json(errorBody("Not found", "NOT_FOUND"), 404);
      }
      if (await hasPublicationReportLock(id)) {
        return c.json(
          errorBody("This card cannot be published", "PUBLIC_CONTENT_NOT_ALLOWED"),
          400,
        );
      }
      let allowed: boolean;
      try {
        allowed = await moderatePublicCard({
          thought: card.thought,
          reframes: card.results.map((result) => result.reframe),
        });
      } catch {
        return c.json(
          errorBody("Public content moderation is unavailable", "PUBLIC_MODERATION_UNAVAILABLE"),
          503,
        );
      }
      if (!allowed) {
        return c.json(
          errorBody("This card cannot be published", "PUBLIC_CONTENT_NOT_ALLOWED"),
          400,
        );
      }
    }
    const result = await patchCard(id, patch);
    if (!result.ok) {
      if (result.reason === "not_found") {
        return c.json(errorBody("Not found", "NOT_FOUND"), 404);
      }
      if (result.reason === "publication_blocked") {
        return c.json(
          errorBody("This card cannot be published", "PUBLIC_CONTENT_NOT_ALLOWED"),
          400,
        );
      }
      return c.json(errorBody("style must be one of the card results", "VALIDATION_ERROR"), 400);
    }
    return c.json(result.card);
  },
);

cardsRoute.post(
  "/:id/report",
  requireAuth,
  zValidator("param", idParamSchema, (result, c) => {
    if (!result.success) {
      return c.json(errorBody(validationErrorMessage(result.error), "VALIDATION_ERROR"), 400);
    }
  }),
  zValidator("json", reportCardSchema, (result, c) => {
    if (!result.success) {
      return c.json(errorBody(validationErrorMessage(result.error), "VALIDATION_ERROR"), 400);
    }
  }),
  async (c) => {
    const { id } = c.req.valid("param");
    const { reason } = c.req.valid("json");
    const result = await reportCard(id, reason);
    if (!result.ok) {
      if (result.reason === "not_found") {
        return c.json(errorBody("Not found", "NOT_FOUND"), 404);
      }
      const message =
        result.reason === "own_card"
          ? "You cannot report your own card"
          : "Private cards cannot be reported";
      return c.json(errorBody(message, "VALIDATION_ERROR"), 400);
    }
    return c.json({ reported: true });
  },
);

cardsRoute.delete(
  "/:id",
  requireAuth,
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
