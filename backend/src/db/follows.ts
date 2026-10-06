import { and, desc, eq, inArray, sql } from "drizzle-orm";
import { getOwnerUserId } from "../lib/authStub.js";
import { avatarUrlFor } from "../lib/avatarUrl.js";
import type { StoredCardAuthor } from "../types/index.js";
import { DbError, getDb, wrapDbError } from "./client.js";
import { lockUserPair, notBlockedBetween, usersAreBlocked } from "./communitySafety.js";
import { followNotifications, follows, users } from "./schema.js";

type Selectable = Pick<ReturnType<typeof getDb>, "select">;

/** Author ids from `authorIds` that `viewerId` follows. The viewer is never included. */
export async function followedAuthorIds(
  viewerId: string,
  authorIds: readonly string[],
  db: Selectable = getDb(),
): Promise<Set<string>> {
  const ids = [...new Set(authorIds)].filter((id) => id !== viewerId);
  if (ids.length === 0) {
    return new Set();
  }
  try {
    const rows = await db
      .select({ followeeId: follows.followeeId })
      .from(follows)
      .where(
        and(
          eq(follows.followerId, viewerId),
          inArray(follows.followeeId, ids),
          notBlockedBetween(viewerId, follows.followeeId),
        ),
      );
    return new Set(rows.map((row) => row.followeeId));
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "followedAuthorIds");
  }
}

/** People the viewer follows, newest follow first. */
export async function listFollowing(): Promise<StoredCardAuthor[]> {
  const viewerId = getOwnerUserId();
  try {
    const rows = await getDb()
      .select({
        id: users.id,
        initials: users.initials,
        avatarKey: users.avatarKey,
      })
      .from(follows)
      .innerJoin(users, eq(users.id, follows.followeeId))
      .where(and(eq(follows.followerId, viewerId), notBlockedBetween(viewerId, follows.followeeId)))
      .orderBy(desc(follows.createdAt), desc(users.id));
    return rows.map((row) => {
      const author: StoredCardAuthor = { id: row.id, initials: row.initials, following: true };
      const avatarUrl = avatarUrlFor(row.id, row.avatarKey);
      if (avatarUrl) {
        author.avatarUrl = avatarUrl;
      }
      return author;
    });
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "listFollowing");
  }
}

export type FollowWriteResult = "ok" | "not_found" | "self" | "blocked";

/** `notificationId` is set only when this call created a follow notification. */
export type FollowWriteOutcome = {
  result: FollowWriteResult;
  notificationId: string | null;
};

function followOutcome(
  result: FollowWriteResult,
  notificationId: string | null = null,
): FollowWriteOutcome {
  return { result, notificationId };
}

export async function followUser(followeeId: string): Promise<FollowWriteOutcome> {
  const followerId = getOwnerUserId();
  if (followeeId === followerId) {
    return followOutcome("self");
  }
  try {
    return await getDb().transaction(async (tx) => {
      await lockUserPair(tx, followerId, followeeId);
      const user = await tx.query.users.findFirst({
        where: eq(users.id, followeeId),
        columns: { id: true },
      });
      if (!user) {
        return followOutcome("not_found");
      }
      if (await usersAreBlocked(followerId, followeeId, tx)) {
        return followOutcome("blocked");
      }
      const inserted = await tx
        .insert(follows)
        .values({ followerId, followeeId })
        .onConflictDoNothing()
        .returning({ followerId: follows.followerId });
      if (inserted.length === 0) {
        return followOutcome("ok");
      }

      const reverse = await tx
        .select({ followerId: follows.followerId })
        .from(follows)
        .where(and(eq(follows.followerId, followeeId), eq(follows.followeeId, followerId)))
        .limit(1);

      let notificationId: string | null = null;
      // A failed notification must not roll back the follow. Postgres aborts the
      // transaction on any error, so the insert sits in its own savepoint.
      await tx.execute(sql`savepoint follow_notification`);
      try {
        const notes = await tx
          .insert(followNotifications)
          .values({
            recipientId: followeeId,
            actorId: followerId,
            followedBack: reverse.length > 0,
          })
          .onConflictDoNothing()
          .returning({ id: followNotifications.id });
        notificationId = notes[0]?.id ?? null;
        await tx.execute(sql`release savepoint follow_notification`);
      } catch (error) {
        await tx.execute(sql`rollback to savepoint follow_notification`);
        console.error("follow_notification_insert_failed", {
          name: error instanceof Error ? error.name : "error",
        });
      }
      return followOutcome("ok", notificationId);
    });
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "followUser");
  }
}

export async function unfollowUser(followeeId: string): Promise<FollowWriteResult> {
  const followerId = getOwnerUserId();
  if (followeeId === followerId) {
    return "self";
  }
  try {
    return await getDb().transaction(async (tx) => {
      await lockUserPair(tx, followerId, followeeId);
      const user = await tx.query.users.findFirst({
        where: eq(users.id, followeeId),
        columns: { id: true },
      });
      if (!user) {
        return "not_found";
      }
      if (await usersAreBlocked(followerId, followeeId, tx)) {
        return "blocked";
      }
      await tx
        .delete(follows)
        .where(and(eq(follows.followerId, followerId), eq(follows.followeeId, followeeId)));
      return "ok";
    });
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "unfollowUser");
  }
}
