import { and, desc, eq, inArray } from "drizzle-orm";
import { getOwnerUserId } from "../lib/authStub.js";
import { avatarUrlFor } from "../lib/avatarUrl.js";
import type { StoredCardAuthor } from "../types/index.js";
import { DbError, getDb, wrapDbError } from "./client.js";
import { follows, users } from "./schema.js";
import { getUserById } from "./users.js";

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
      .where(and(eq(follows.followerId, viewerId), inArray(follows.followeeId, ids)));
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
      .where(eq(follows.followerId, viewerId))
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

export type FollowWriteResult = "ok" | "not_found" | "self";

export async function followUser(followeeId: string): Promise<FollowWriteResult> {
  const followerId = getOwnerUserId();
  if (followeeId === followerId) {
    return "self";
  }
  try {
    const user = await getUserById(followeeId);
    if (!user) {
      return "not_found";
    }
    await getDb().insert(follows).values({ followerId, followeeId }).onConflictDoNothing();
    return "ok";
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
    const user = await getUserById(followeeId);
    if (!user) {
      return "not_found";
    }
    await getDb()
      .delete(follows)
      .where(and(eq(follows.followerId, followerId), eq(follows.followeeId, followeeId)));
    return "ok";
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "unfollowUser");
  }
}
