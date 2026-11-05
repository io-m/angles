import { randomBytes } from "node:crypto";
import { zValidator } from "@hono/zod-validator";
import { Hono } from "hono";
import { z } from "zod";
import { listStack } from "../db/stack.js";
import { requireAuth } from "../lib/authStub.js";
import { decodeFeedSession, encodeFeedSession, rankingEnabled } from "../lib/feedRanking.js";
import { errorBody, validationErrorMessage } from "../lib/http.js";
import { CATEGORIES, EMOTIONS, type FeedSessionCursor, type StackResponse } from "../types/index.js";

export const STACK_PAGE_SIZE = 12;

/** Ids a page request may name as already handed out. More than any visit needs. */
const MAX_SEEN = 200;

/** A new visit: its own jitter, and every ranking input frozen at this moment. */
function newStackSession(): FeedSessionCursor {
  return { seed: randomBytes(12).toString("base64url"), startedAt: new Date() };
}

const sessionSchema = z.string().transform((raw, context): FeedSessionCursor => {
  const session = decodeFeedSession(raw);
  if (!session) {
    context.addIssue({ code: "custom", message: "session must be one from a previous page" });
    return z.NEVER;
  }
  return session;
});

const seenSchema = z.string().transform((raw, context): string[] => {
  const ids = raw.length === 0 ? [] : raw.split(",");
  if (ids.length > MAX_SEEN || ids.some((id) => !z.uuid().safeParse(id).success)) {
    context.addIssue({
      code: "custom",
      message: `seen must be at most ${MAX_SEEN} comma-separated card ids`,
    });
    return z.NEVER;
  }
  return ids;
});

/** A comma-separated subset of `values`, returned in their own order. */
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

const stackQuerySchema = z
  .object({
    limit: z.coerce.number().int().min(1).max(50).optional().default(STACK_PAGE_SIZE),
    session: sessionSchema.optional(),
    seen: seenSchema.optional(),
    categories: enumCsvSchema(CATEGORIES).optional(),
    emotions: enumCsvSchema(EMOTIONS).optional(),
  })
  .strict();

export const stackRoute = new Hono();

stackRoute.get(
  "/",
  requireAuth,
  zValidator("query", stackQuerySchema, (result, c) => {
    if (!result.success) {
      return c.json(errorBody(validationErrorMessage(result.error), "VALIDATION_ERROR"), 400);
    }
  }),
  async (c) => {
    const query = c.req.valid("query");
    const session = query.session ?? newStackSession();
    const page = await listStack(
      {
        limit: query.limit,
        session,
        seen: query.seen ?? [],
        categories: query.categories,
        emotions: query.emotions,
      },
      rankingEnabled(),
    );
    return c.json({
      cards: page.cards,
      session: encodeFeedSession(session),
      exhausted: page.exhausted,
    } satisfies StackResponse);
  },
);
