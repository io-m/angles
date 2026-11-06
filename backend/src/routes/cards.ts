import { zValidator } from "@hono/zod-validator";
import { Hono } from "hono";
import { z } from "zod";
import { reportCard } from "../db/communitySafety.js";
import { clearDecision, writeDecision } from "../db/decisions.js";
import { scheduleLovePush } from "../db/loveNotifications.js";
import {
  createCard,
  deleteCard,
  findOwnCardByCookSignature,
  getCard,
  hasPublicationReportLock,
  listCards,
  ownerPublishingSuspended,
  patchCard,
} from "../db/cards.js";
import { getOwnerUserId, requireAuth } from "../lib/authStub.js";
import { signedMetaSchema } from "../lib/cookSchema.js";
import { verifyCook } from "../lib/cookSignature.js";
import { cardCursorSchema } from "../lib/cursor.js";
import { errorBody, validationErrorMessage } from "../lib/http.js";
import { LLM_MODEL_IDS } from "../lib/llmClient.js";
import { REPORT_REASONS } from "../lib/communitySafetyTypes.js";
import { moderatePublicCard } from "../lib/publicModeration.js";
import { announceReport } from "../lib/reportAlerts.js";
import { shownStyleSchema } from "../lib/styleSet.js";
import {
  CATEGORIES,
  DECISION_KINDS,
  MAX_PASSES,
  STYLES,
  type DecisionResponse,
} from "../types/index.js";

const MAX_THOUGHT_LENGTH = 2000;
const MAX_REFRAME_LENGTH = 4000;

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
          style: shownStyleSchema(),
          reframe: z
            .string()
            .transform((value) => value.trim())
            .pipe(z.string().min(1, "reframe must not be empty").max(MAX_REFRAME_LENGTH)),
          reframeOriginal: z
            .string()
            .transform((value) => value.trim())
            .pipe(z.string().min(1).max(MAX_REFRAME_LENGTH))
            .optional(),
          signature: z.string().min(1).max(128),
        }),
      )
      .min(1)
      .max(STYLES.length)
      .refine((items) => new Set(items.map((item) => item.style)).size === items.length, {
        message: "results must not repeat a style",
      }),
    meta: signedMetaSchema,
    signature: z.string().min(1).max(128),
    model: z.enum(LLM_MODEL_IDS),
    spotlightStyle: shownStyleSchema(),
    isPublic: z.boolean().optional(),
  })
  .refine((body) => body.results.some((item) => item.style === body.spotlightStyle), {
    message: "spotlightStyle must be one of the results",
  });

const listQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(500).optional().default(50),
  before: cardCursorSchema().optional(),
  category: z.enum(CATEGORIES).optional(),
  style: shownStyleSchema().optional(),
  saved: z
    .enum(["true", "false"])
    .optional()
    .transform((value) => (value === undefined ? undefined : value === "true")),
});

const idParamSchema = z.object({
  id: z.uuid(),
});

const patchCardSchema = z
  .object({
    isPublic: z.boolean(),
  })
  .strict();

/**
 * The whole decision row as the phone wants it stored, so a retry and a rewind are the
 * same write. A pass counts itself; a save keeps the passes before it.
 */
const decisionSchema = z
  .object({
    kind: z.enum(DECISION_KINDS),
    style: shownStyleSchema(),
    checkedStyles: z
      .array(shownStyleSchema())
      .min(1)
      .max(STYLES.length)
      .refine((styles) => new Set(styles).size === styles.length, {
        message: "checkedStyles must not repeat a style",
      }),
    passes: z.number().int().min(0).max(MAX_PASSES),
  })
  .strict()
  .refine((body) => body.kind !== "pass" || body.passes >= 1, {
    message: "a pass must count at least one pass",
    path: ["passes"],
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
    if (
      rest.meta.safety !== "none" ||
      !verifyCook({ ...rest, ownerId: getOwnerUserId(), signature, results })
    ) {
      return c.json(errorBody("card does not match a reframe from this server", "VALIDATION_ERROR"), 400);
    }
    // A retried save whose first response was lost gets the card it already made.
    const existing = await findOwnCardByCookSignature(signature);
    if (existing) {
      return c.json(existing, 200);
    }
    if (rest.isPublic === true) {
      if (await ownerPublishingSuspended()) {
        return c.json(
          errorBody("This card cannot be published", "PUBLIC_CONTENT_NOT_ALLOWED"),
          400,
        );
      }
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
    const card = await createCard(
      {
        ...rest,
        results: results.map(({ signature: _signature, ...result }) => result),
      },
      { cookSignature: signature },
    );
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
      saved: query.saved,
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
      if ((await hasPublicationReportLock(id)) || (await ownerPublishingSuspended())) {
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
      return c.json(
        errorBody("This card cannot be published", "PUBLIC_CONTENT_NOT_ALLOWED"),
        400,
      );
    }
    return c.json(result.card);
  },
);

cardsRoute.put(
  "/:id/decision",
  requireAuth,
  zValidator("param", idParamSchema, (result, c) => {
    if (!result.success) {
      return c.json(errorBody(validationErrorMessage(result.error), "VALIDATION_ERROR"), 400);
    }
  }),
  zValidator("json", decisionSchema, (result, c) => {
    if (!result.success) {
      return c.json(errorBody(validationErrorMessage(result.error), "VALIDATION_ERROR"), 400);
    }
  }),
  async (c) => {
    const { id } = c.req.valid("param");
    const result = await writeDecision(id, c.req.valid("json"));
    if (!result.ok) {
      switch (result.reason) {
        case "not_found":
          return c.json(errorBody("Not found", "NOT_FOUND"), 404);
        case "own_card":
          return c.json(errorBody("You cannot save or pass your own card", "VALIDATION_ERROR"), 400);
        case "not_public":
          return c.json(errorBody("Private cards cannot be saved or passed", "VALIDATION_ERROR"), 400);
        case "unknown_style":
          return c.json(errorBody("styles must be among the card results", "VALIDATION_ERROR"), 400);
      }
    }
    if (result.loved) {
      scheduleLovePush(id);
    }
    return c.json({ decision: result.decision } satisfies DecisionResponse);
  },
);

cardsRoute.delete(
  "/:id/decision",
  requireAuth,
  zValidator("param", idParamSchema, (result, c) => {
    if (!result.success) {
      return c.json(errorBody(validationErrorMessage(result.error), "VALIDATION_ERROR"), 400);
    }
  }),
  async (c) => {
    const { id } = c.req.valid("param");
    const result = await clearDecision(id);
    if (!result.ok) {
      return c.json(errorBody("Not found", "NOT_FOUND"), 404);
    }
    return c.body(null, 204);
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
    if (result.created) {
      announceReport({ cardId: id, reason, madePrivate: result.madePrivate });
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
