import { randomBytes } from "node:crypto";
import { zValidator } from "@hono/zod-validator";
import { Hono } from "hono";
import { z } from "zod";
import {
  clearFeedSaves,
  listFeed,
  listRankedFeed,
  saveFeedAngle,
  unsaveFeedAngle,
} from "../db/feed.js";
import { requireAuth } from "../lib/authStub.js";
import { cardCursorSchema } from "../lib/cursor.js";
import {
  decodeFeedSession,
  encodeFeedSession,
  rankingEnabled,
} from "../lib/feedRanking.js";
import { errorBody, validationErrorMessage } from "../lib/http.js";
import {
  CATEGORIES,
  EMOTIONS,
  STYLES,
  type FeedCursor,
  type FeedListResponse,
  type FeedSessionCursor,
} from "../types/index.js";

/**
 * One visit's ranking order. The seed keeps it stable while scrolling and different on
 * the next visit; `startedAt` freezes the candidate set so offset paging stays exact.
 */
function newFeedSession(): FeedSessionCursor {
  return { seed: randomBytes(12).toString("base64url"), startedAt: new Date(), offset: 0 };
}

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

/**
 * `before` carries whichever page pointer the last response handed out: a `createdAt|id`
 * keyset in chronological mode, an opaque ranked session in resonance mode. One param,
 * because the client echoes the cursor back without reading it.
 */
function pagePointerSchema() {
  return z.string().transform((raw, context): FeedPagePointer => {
    const session = decodeFeedSession(raw);
    if (session) {
      return { session };
    }
    const keyset = cardCursorSchema().safeParse(raw);
    if (keyset.success) {
      return { before: keyset.data };
    }
    context.addIssue({
      code: "custom",
      message:
        "before must be an ISO-8601 timestamp and UUID separated by |, or a cursor from a previous page",
    });
    return z.NEVER;
  });
}

type FeedPagePointer = { session: FeedSessionCursor } | { before: FeedCursor };

const listQuerySchema = z
  .object({
    limit: z.coerce.number().int().min(1).max(500).optional().default(200),
    before: pagePointerSchema().optional(),
    after: cardCursorSchema().optional(),
    categories: enumCsvSchema(CATEGORIES).optional(),
    emotions: enumCsvSchema(EMOTIONS).optional(),
    style: z.enum(STYLES).optional(),
  })
  .strict()
  // Paging backwards and forwards at once has no meaning, and silently honouring one
  // would hide a client bug behind a plausible-looking page.
  .refine((query) => !(query.before && query.after), {
    message: "before and after cannot be combined",
    path: ["after"],
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
  requireAuth,
  zValidator("query", listQuerySchema, (result, c) => {
    if (!result.success) {
      return c.json(errorBody(validationErrorMessage(result.error), "VALIDATION_ERROR"), 400);
    }
  }),
  async (c) => {
    const query = c.req.valid("query");
    const pointer = query.before;
    const facets = {
      limit: query.limit,
      categories: query.categories,
      emotions: query.emotions,
      style: query.style,
    };

    // Chronological when: ranking is off, the client is asking for arrivals (strictly
    // newer, newest first — a new post must not be able to rank out of sight), or the
    // client is mid-scroll on a keyset cursor and must not be yanked into another order.
    const keyset = pointer && "before" in pointer ? pointer.before : undefined;
    if (query.after || keyset || !rankingEnabled()) {
      const cardList = await listFeed({ ...facets, before: keyset, after: query.after });
      return c.json({ cards: cardList } satisfies FeedListResponse);
    }

    // A ranked order cannot be derived from the cards, so the server owns the pointer.
    const session = pointer && "session" in pointer ? pointer.session : newFeedSession();
    const cardList = await listRankedFeed({ ...facets, session });
    return c.json({
      cards: cardList,
      page: {
        nextCursor: encodeFeedSession({
          ...session,
          offset: session.offset + cardList.length,
        }),
      },
    } satisfies FeedListResponse);
  },
);

feedRoute.put(
  "/cards/:id/angles/:style",
  requireAuth,
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
  requireAuth,
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
  requireAuth,
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
