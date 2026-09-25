import { zValidator } from "@hono/zod-validator";
import { Hono } from "hono";
import { z } from "zod";
import { listPublicCardsForUser } from "../db/feed.js";
import { followedAuthorIds, followUser, unfollowUser } from "../db/follows.js";
import { authorOf } from "../db/mapCard.js";
import { getUserById } from "../db/users.js";
import { getOwnerUserId, requireAuth } from "../lib/authStub.js";
import { errorBody, validationErrorMessage } from "../lib/http.js";
import { cardCursorSchema } from "../lib/cursor.js";
import type { AuthorCardsResponse, FollowStateResponse } from "../types/index.js";

const paramsSchema = z.object({
  id: z.uuid(),
});

const querySchema = z
  .object({
    limit: z.coerce.number().int().min(1).max(500).optional().default(24),
    before: cardCursorSchema().optional(),
  })
  .strict();

export const usersRoute = new Hono();

usersRoute.get(
  "/:id/cards",
  requireAuth,
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
    const viewerId = getOwnerUserId();
    const following =
      id !== viewerId &&
      (cards[0]?.author.following ?? (await followedAuthorIds(viewerId, [id])).has(id));
    const body: AuthorCardsResponse = {
      user: authorOf(user.id, user, following),
      cards,
    };
    return c.json(body);
  },
);

usersRoute.put(
  "/:id/follow",
  requireAuth,
  zValidator("param", paramsSchema, (result, c) => {
    if (!result.success) {
      return c.json(errorBody(validationErrorMessage(result.error), "VALIDATION_ERROR"), 400);
    }
  }),
  async (c) => {
    const { id } = c.req.valid("param");
    if (id === getOwnerUserId()) {
      return c.json(errorBody("You cannot follow yourself", "VALIDATION_ERROR"), 400);
    }
    const result = await followUser(id);
    if (result === "not_found") {
      return c.json(errorBody("Not found", "NOT_FOUND"), 404);
    }
    if (result === "self") {
      return c.json(errorBody("You cannot follow yourself", "VALIDATION_ERROR"), 400);
    }
    const body: FollowStateResponse = { following: true };
    return c.json(body);
  },
);

usersRoute.delete(
  "/:id/follow",
  requireAuth,
  zValidator("param", paramsSchema, (result, c) => {
    if (!result.success) {
      return c.json(errorBody(validationErrorMessage(result.error), "VALIDATION_ERROR"), 400);
    }
  }),
  async (c) => {
    const { id } = c.req.valid("param");
    if (id === getOwnerUserId()) {
      return c.json(errorBody("You cannot follow yourself", "VALIDATION_ERROR"), 400);
    }
    const result = await unfollowUser(id);
    if (result === "not_found") {
      return c.json(errorBody("Not found", "NOT_FOUND"), 404);
    }
    if (result === "self") {
      return c.json(errorBody("You cannot follow yourself", "VALIDATION_ERROR"), 400);
    }
    const body: FollowStateResponse = { following: false };
    return c.json(body);
  },
);
