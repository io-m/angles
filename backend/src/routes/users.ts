import { zValidator } from "@hono/zod-validator";
import { Hono } from "hono";
import { z } from "zod";
import { listPublicCardsForUser } from "../db/feed.js";
import { authorOf } from "../db/mapCard.js";
import { getUserById } from "../db/users.js";
import { authStub } from "../lib/authStub.js";
import { errorBody, validationErrorMessage } from "../lib/http.js";
import type { AuthorCardsResponse, FeedCursor } from "../types/index.js";

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

const paramsSchema = z.object({
  id: z.uuid(),
});

const querySchema = z
  .object({
    limit: z.coerce.number().int().min(1).max(500).optional().default(24),
    before: feedCursorSchema().optional(),
  })
  .strict();

export const usersRoute = new Hono();

usersRoute.get(
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
    const user = await getUserById(id);
    if (!user) {
      return c.json(errorBody("Not found", "NOT_FOUND"), 404);
    }

    const cards = await listPublicCardsForUser({
      userId: id,
      limit: query.limit,
      before: query.before,
    });
    const body: AuthorCardsResponse = {
      user: authorOf(user.id, user),
      cards,
    };
    return c.json(body);
  },
);
