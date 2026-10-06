import { and, count, desc, eq, isNull, lte, ne, notExists, sql } from "drizzle-orm";
import { alias } from "drizzle-orm/pg-core";
import {
  apnsConfigFromEnv,
  followPushAlertText,
  sendApnsAlert,
  type FollowPushAlert,
} from "../lib/apns.js";
import { getOwnerUserId } from "../lib/authStub.js";
import { avatarUrlFor } from "../lib/avatarUrl.js";
import type {
  FollowNotificationItem,
  FollowNotificationsResponse,
  PushEnvironment,
} from "../types/index.js";
import { DbError, getDb, wrapDbError } from "./client.js";
import { notBlockedBetween, usersAreBlocked } from "./communitySafety.js";
import { followedAuthorIds } from "./follows.js";
import { deviceTokens, followNotifications, users } from "./schema.js";

const LIST_LIMIT = 100;
const newerNotification = alias(followNotifications, "newer_notification");

export type PushSender = (alert: FollowPushAlert) => Promise<"sent" | "unregistered" | "skipped" | "failed">;

/**
 * `throughId` reads every row up to the newest one on screen, compared in SQL at full
 * precision. `before` is the build 18 shape: a millisecond stamp of a microsecond column.
 */
export type FollowReadMark = { throughId: string } | { before: Date };

type Selectable = Pick<ReturnType<typeof getDb>, "select">;

/** The badge number. Counts what the list can show, so the two always agree. */
async function unreadFollowCount(recipientId: string, db: Selectable): Promise<number> {
  const [unread] = await db
    .select({ value: count() })
    .from(followNotifications)
    .where(
      and(
        eq(followNotifications.recipientId, recipientId),
        isNull(followNotifications.readAt),
        notBlockedBetween(recipientId, followNotifications.actorId),
      ),
    );
  return Number(unread?.value ?? 0);
}

export async function listFollowNotifications(): Promise<FollowNotificationsResponse> {
  const viewerId = getOwnerUserId();
  try {
    const db = getDb();
    const rows = await db
      .select({
        id: followNotifications.id,
        createdAt: followNotifications.createdAt,
        readAt: followNotifications.readAt,
        followedBack: followNotifications.followedBack,
        actorId: users.id,
        initials: users.initials,
        name: users.name,
        avatarKey: users.avatarKey,
      })
      .from(followNotifications)
      .innerJoin(users, eq(users.id, followNotifications.actorId))
      .where(
        and(
          eq(followNotifications.recipientId, viewerId),
          notBlockedBetween(viewerId, followNotifications.actorId),
          // One row per person: their newest follow. Older ones stay stored for read state.
          notExists(
            db
              .select({ id: newerNotification.id })
              .from(newerNotification)
              .where(
                and(
                  eq(newerNotification.recipientId, followNotifications.recipientId),
                  eq(newerNotification.actorId, followNotifications.actorId),
                  sql`(${newerNotification.createdAt}, ${newerNotification.id})
                      > (${followNotifications.createdAt}, ${followNotifications.id})`,
                ),
              ),
          ),
        ),
      )
      .orderBy(desc(followNotifications.createdAt), desc(followNotifications.id))
      .limit(LIST_LIMIT);

    const unreadCount = await unreadFollowCount(viewerId, db);

    const following = await followedAuthorIds(
      viewerId,
      rows.map((row) => row.actorId),
      db,
    );

    return {
      unreadCount,
      notifications: rows.map((row) => toItem(row, following.has(row.actorId))),
    };
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "listFollowNotifications");
  }
}

/** Returns the unread count left after the mark. */
export async function markFollowNotificationsRead(mark: FollowReadMark): Promise<number> {
  const viewerId = getOwnerUserId();
  const upTo =
    "throughId" in mark
      ? lte(
          followNotifications.createdAt,
          sql`(select ${followNotifications.createdAt} from ${followNotifications}
               where ${followNotifications.id} = ${mark.throughId}
                 and ${followNotifications.recipientId} = ${viewerId})`,
        )
      : sql`date_trunc('milliseconds', ${followNotifications.createdAt})
            <= ${mark.before.toISOString()}::timestamptz + interval '1 millisecond'`;
  try {
    const db = getDb();
    await db
      .update(followNotifications)
      .set({ readAt: new Date() })
      .where(
        and(
          eq(followNotifications.recipientId, viewerId),
          isNull(followNotifications.readAt),
          upTo,
        ),
      );
    return await unreadFollowCount(viewerId, db);
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "markFollowNotificationsRead");
  }
}

export async function registerDeviceToken(
  token: string,
  environment: PushEnvironment,
): Promise<void> {
  const userId = getOwnerUserId();
  try {
    await getDb().transaction(async (tx) => {
      await tx
        .insert(deviceTokens)
        .values({ token, userId, environment, updatedAt: new Date() })
        .onConflictDoUpdate({
          target: deviceTokens.token,
          set: { userId, environment, updatedAt: new Date() },
        });
      // One live token per account and APNs environment. Stale rows from earlier
      // installs otherwise get a 200 from Apple with no banner on this phone.
      await tx
        .delete(deviceTokens)
        .where(
          and(
            eq(deviceTokens.userId, userId),
            eq(deviceTokens.environment, environment),
            ne(deviceTokens.token, token),
          ),
        );
    });
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "registerDeviceToken");
  }
}

export async function unregisterDeviceToken(token: string): Promise<void> {
  const userId = getOwnerUserId();
  try {
    await getDb()
      .delete(deviceTokens)
      .where(and(eq(deviceTokens.token, token), eq(deviceTokens.userId, userId)));
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "unregisterDeviceToken");
  }
}

export async function setNotifyFollows(enabled: boolean): Promise<boolean> {
  try {
    const [row] = await getDb()
      .update(users)
      .set({ notifyFollows: enabled, updatedAt: new Date() })
      .where(eq(users.id, getOwnerUserId()))
      .returning({ notifyFollows: users.notifyFollows });
    if (!row) {
      throw new DbError("Database error");
    }
    return row.notifyFollows;
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "setNotifyFollows");
  }
}

/**
 * Best-effort push for a notification row that is already committed.
 * Missing config, a disabled switch, no token, or a block sends nothing.
 */
export async function deliverFollowPush(
  notificationId: string,
  send: PushSender = sendApnsAlert,
): Promise<void> {
  try {
    const db = getDb();
    const [row] = await db
      .select({
        id: followNotifications.id,
        followedBack: followNotifications.followedBack,
        recipientId: followNotifications.recipientId,
        actorId: followNotifications.actorId,
        initials: users.initials,
        name: users.name,
      })
      .from(followNotifications)
      .innerJoin(users, eq(users.id, followNotifications.actorId))
      .where(eq(followNotifications.id, notificationId))
      .limit(1);
    if (!row) {
      return;
    }

    const [recipient] = await db
      .select({ notifyFollows: users.notifyFollows })
      .from(users)
      .where(eq(users.id, row.recipientId))
      .limit(1);
    if (!recipient?.notifyFollows) {
      logPushSkipped("switch_off");
      return;
    }
    if (await usersAreBlocked(row.recipientId, row.actorId)) {
      logPushSkipped("blocked");
      return;
    }

    const tokens = await db
      .select({ token: deviceTokens.token, environment: deviceTokens.environment })
      .from(deviceTokens)
      .where(eq(deviceTokens.userId, row.recipientId));
    if (tokens.length === 0) {
      logPushSkipped("no_token");
      return;
    }
    if (!apnsConfigFromEnv()) {
      logPushSkipped("no_config");
      return;
    }

    const alertText = followPushAlertText(row.name, row.initials, row.followedBack);
    const badge = await unreadFollowCount(row.recipientId, db);

    for (const device of tokens) {
      const result = await send({
        token: device.token,
        environment: device.environment,
        collapseId: row.id,
        title: alertText.title,
        body: alertText.body,
        badge,
        notificationId: row.id,
        actorId: row.actorId,
      });
      if (result === "unregistered") {
        await db.delete(deviceTokens).where(eq(deviceTokens.token, device.token));
      }
    }
  } catch (error) {
    console.error("follow_push_failed", {
      name: error instanceof Error ? error.name : "error",
    });
  }
}

/** No ids, tokens, or initials: only which gate stopped the push. */
function logPushSkipped(reason: "switch_off" | "blocked" | "no_token" | "no_config"): void {
  console.log("follow_push_skipped", { reason });
}

function toItem(
  row: {
    id: string;
    createdAt: Date;
    readAt: Date | null;
    followedBack: boolean;
    actorId: string;
    initials: string;
    name: string;
    avatarKey: string | null;
  },
  following: boolean,
): FollowNotificationItem {
  const trimmedName = row.name.trim();
  const actor: FollowNotificationItem["actor"] = {
    id: row.actorId,
    initials: row.initials,
    following,
  };
  if (trimmedName) {
    actor.displayName = trimmedName;
  }
  const avatarUrl = avatarUrlFor(row.actorId, row.avatarKey);
  if (avatarUrl) {
    actor.avatarUrl = avatarUrl;
  }
  return {
    id: row.id,
    createdAt: row.createdAt.toISOString(),
    readAt: row.readAt ? row.readAt.toISOString() : null,
    followedBack: row.followedBack,
    actor,
  };
}
