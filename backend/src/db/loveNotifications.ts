import { and, desc, eq, exists, inArray, isNull, lte, max, sql } from "drizzle-orm";
import {
  apnsConfigFromEnv,
  followActorPublicName,
  lovePushAlertText,
  sendApnsAlert,
} from "../lib/apns.js";
import { getOwnerUserId } from "../lib/authStub.js";
import { avatarUrlFor } from "../lib/avatarUrl.js";
import type { LoveNotificationItem, Style } from "../types/index.js";
import { DbError, getDb, wrapDbError } from "./client.js";
import { notBlockedBetween, usersAreBlocked, type AppTransaction } from "./communitySafety.js";
import type { PushSender } from "./followNotifications.js";
import { followedAuthorIds } from "./follows.js";
import { unreadNotificationCount } from "./notificationCounts.js";
import { cardDecisions, cards, deviceTokens, loveNotifications, users } from "./schema.js";

type Selectable = Pick<ReturnType<typeof getDb>, "select">;

const LIST_LIMIT = 100;

/**
 * How long a love waits before it may push. A swipe right and a Rewind a moment later
 * must not tell the author anything, and loves that land together become one push.
 */
export const LOVE_PUSH_DELAY_MS = 2 * 60_000;
/** At most one push per card in this window; the in-app list still gets every love. */
export const LOVE_PUSH_THROTTLE_MS = 30 * 60_000;
/** A love older than this that never pushed (the server was down) is not pushed late. */
const LOVE_PUSH_MAX_AGE_MS = 60 * 60_000;

/**
 * A save that was not a save before. Stores one unread row for the author unless one for
 * this lover and card is already unread. Never fails the decision it belongs to: a failure
 * is rolled back to a savepoint and logged without ids.
 */
export async function recordLove(
  tx: AppTransaction,
  love: { recipientId: string; actorId: string; cardId: string; style: Style },
): Promise<boolean> {
  await tx.execute(sql`savepoint love_notification`);
  try {
    const inserted = await tx
      .insert(loveNotifications)
      .values(love)
      .onConflictDoNothing()
      .returning({ id: loveNotifications.id });
    await tx.execute(sql`release savepoint love_notification`);
    return inserted.length > 0;
  } catch (error) {
    await tx.execute(sql`rollback to savepoint love_notification`);
    console.error("love_notification_insert_failed", {
      name: error instanceof Error ? error.name : "error",
    });
    return false;
  }
}

/** The save was taken back: a love nobody has read yet goes away with it. */
export async function retractLove(
  db: Pick<ReturnType<typeof getDb>, "delete">,
  actorId: string,
  cardId: string,
): Promise<void> {
  await db
    .delete(loveNotifications)
    .where(
      and(
        eq(loveNotifications.actorId, actorId),
        eq(loveNotifications.cardId, cardId),
        isNull(loveNotifications.readAt),
      ),
    );
}

/** The newest loves on the viewer's own posts. A lover who keeps their name off is unnamed. */
export async function listLoveNotifications(
  viewerId: string,
  db: Selectable = getDb(),
): Promise<LoveNotificationItem[]> {
  const rows = await db
    .select({
      id: loveNotifications.id,
      createdAt: loveNotifications.createdAt,
      readAt: loveNotifications.readAt,
      style: loveNotifications.style,
      cardId: loveNotifications.cardId,
      thought: cards.thoughtEn,
      thoughtOriginal: cards.thoughtOriginal,
      actorId: users.id,
      initials: users.initials,
      name: users.name,
      avatarKey: users.avatarKey,
      shareLoveName: users.shareLoveName,
    })
    .from(loveNotifications)
    .innerJoin(users, eq(users.id, loveNotifications.actorId))
    .innerJoin(cards, eq(cards.id, loveNotifications.cardId))
    .where(
      and(
        eq(loveNotifications.recipientId, viewerId),
        eq(cards.userId, viewerId),
        notBlockedBetween(viewerId, loveNotifications.actorId),
      ),
    )
    .orderBy(desc(loveNotifications.createdAt), desc(loveNotifications.id))
    .limit(LIST_LIMIT);

  const following = await followedAuthorIds(
    viewerId,
    rows.filter((row) => row.shareLoveName).map((row) => row.actorId),
    db,
  );
  return rows.map((row): LoveNotificationItem => {
    const item: LoveNotificationItem = {
      id: row.id,
      createdAt: row.createdAt.toISOString(),
      readAt: row.readAt ? row.readAt.toISOString() : null,
      style: row.style,
      // The viewer's own card, in their own words.
      card: { id: row.cardId, thought: row.thoughtOriginal ?? row.thought },
    };
    if (row.shareLoveName) {
      const actor: NonNullable<LoveNotificationItem["actor"]> = {
        id: row.actorId,
        initials: row.initials,
        following: following.has(row.actorId),
      };
      const name = row.name.trim();
      if (name) {
        actor.displayName = name;
      }
      const avatarUrl = avatarUrlFor(row.actorId, row.avatarKey);
      if (avatarUrl) {
        actor.avatarUrl = avatarUrl;
      }
      item.actor = actor;
    }
    return item;
  });
}

/** Reads every love up to the newest one on screen. Returns the unread count left, all kinds. */
export async function markLoveNotificationsRead(throughId: string): Promise<number> {
  const viewerId = getOwnerUserId();
  try {
    const db = getDb();
    await db
      .update(loveNotifications)
      .set({ readAt: new Date() })
      .where(
        and(
          eq(loveNotifications.recipientId, viewerId),
          isNull(loveNotifications.readAt),
          lte(
            loveNotifications.createdAt,
            sql`(select ${loveNotifications.createdAt} from ${loveNotifications}
                 where ${loveNotifications.id} = ${throughId}
                   and ${loveNotifications.recipientId} = ${viewerId})`,
          ),
        ),
      );
    return await unreadNotificationCount(viewerId, db);
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "markLoveNotificationsRead");
  }
}

const scheduled = new Set<string>();

/** Pushes this card's new loves after `LOVE_PUSH_DELAY_MS`. One timer per card at a time. */
export function scheduleLovePush(cardId: string, delayMs: number = LOVE_PUSH_DELAY_MS): void {
  if (scheduled.has(cardId)) {
    return;
  }
  scheduled.add(cardId);
  const timer = setTimeout(() => {
    scheduled.delete(cardId);
    void deliverLovePushes(cardId);
  }, delayMs);
  timer.unref();
}

/**
 * One push for a card's loves that have not pushed, are still unread, and whose save still
 * stands. Inside a card's quiet window the run waits for its end instead. Rows are claimed
 * (`pushed_at`) before anything is sent, so two runs cannot both push them; a claimed row
 * a gate stops is simply never pushed. Best-effort: nothing here can fail a request.
 */
export async function deliverLovePushes(
  cardId: string,
  send: PushSender = sendApnsAlert,
  now: Date = new Date(),
): Promise<"sent" | "none" | "throttled" | "skipped"> {
  try {
    const db = getDb();
    const rows = await db
      .select({
        id: loveNotifications.id,
        recipientId: loveNotifications.recipientId,
        actorId: loveNotifications.actorId,
        name: users.name,
        initials: users.initials,
        shareLoveName: users.shareLoveName,
      })
      .from(loveNotifications)
      .innerJoin(users, eq(users.id, loveNotifications.actorId))
      .where(
        and(
          eq(loveNotifications.cardId, cardId),
          isNull(loveNotifications.pushedAt),
          isNull(loveNotifications.readAt),
          exists(
            db
              .select({ one: sql`1` })
              .from(cardDecisions)
              .where(
                and(
                  eq(cardDecisions.userId, loveNotifications.actorId),
                  eq(cardDecisions.cardId, loveNotifications.cardId),
                  eq(cardDecisions.kind, "save"),
                ),
              ),
          ),
        ),
      )
      .orderBy(desc(loveNotifications.createdAt), desc(loveNotifications.id));
    if (rows.length === 0) {
      return "none";
    }
    const [last] = await db
      .select({ at: max(loveNotifications.pushedAt) })
      .from(loveNotifications)
      .where(eq(loveNotifications.cardId, cardId));
    const quietUntil = last?.at ? last.at.getTime() + LOVE_PUSH_THROTTLE_MS : 0;
    if (quietUntil > now.getTime()) {
      // Everything that lands in the quiet window goes out together when it ends.
      scheduleLovePush(cardId, quietUntil - now.getTime());
      logLovePushSkipped("throttled");
      return "throttled";
    }
    const claimed = await db
      .update(loveNotifications)
      .set({ pushedAt: now })
      .where(
        and(
          inArray(
            loveNotifications.id,
            rows.map((row) => row.id),
          ),
          isNull(loveNotifications.pushedAt),
        ),
      )
      .returning({ id: loveNotifications.id });
    const claimedIds = new Set(claimed.map((row) => row.id));
    const fresh = rows.filter((row) => claimedIds.has(row.id));
    const newest = fresh[0];
    if (!newest) {
      return "none";
    }

    const recipientId = newest.recipientId;
    const [recipient] = await db
      .select({ notifyLoves: users.notifyLoves })
      .from(users)
      .where(eq(users.id, recipientId))
      .limit(1);
    if (!recipient?.notifyLoves) {
      logLovePushSkipped("switch_off");
      return "skipped";
    }
    const visible: typeof fresh = [];
    for (const row of fresh) {
      if (!(await usersAreBlocked(recipientId, row.actorId, db))) {
        visible.push(row);
      }
    }
    const lead = visible[0];
    if (!lead) {
      logLovePushSkipped("blocked");
      return "skipped";
    }
    const tokens = await db
      .select({ token: deviceTokens.token, environment: deviceTokens.environment })
      .from(deviceTokens)
      .where(eq(deviceTokens.userId, recipientId));
    if (tokens.length === 0) {
      logLovePushSkipped("no_token");
      return "skipped";
    }
    if (!apnsConfigFromEnv()) {
      logLovePushSkipped("no_config");
      return "skipped";
    }

    const names = visible.map((row) =>
      row.shareLoveName ? followActorPublicName(row.name, row.initials) : null,
    );
    const text = lovePushAlertText(names);
    const badge = await unreadNotificationCount(recipientId, db);
    for (const device of tokens) {
      const result = await send({
        token: device.token,
        environment: device.environment,
        collapseId: `love-${cardId}`,
        title: text.title,
        body: text.body,
        badge,
        notificationId: lead.id,
        category: "love",
        ...(visible.length === 1 && lead.shareLoveName ? { actorId: lead.actorId } : {}),
        cardId,
      });
      if (result === "unregistered") {
        await db.delete(deviceTokens).where(eq(deviceTokens.token, device.token));
      }
    }
    return "sent";
  } catch (error) {
    console.error("love_push_failed", {
      name: error instanceof Error ? error.name : "error",
    });
    return "skipped";
  }
}

/**
 * At startup: loves a restart caught inside their delay push now, and anything older is
 * marked as pushed so it never arrives hours late.
 */
export async function deliverPendingLovePushes(now: Date = new Date()): Promise<void> {
  try {
    const db = getDb();
    const oldest = new Date(now.getTime() - LOVE_PUSH_MAX_AGE_MS);
    await db
      .update(loveNotifications)
      .set({ pushedAt: now })
      .where(and(isNull(loveNotifications.pushedAt), lte(loveNotifications.createdAt, oldest)));
    const pending = await db
      .selectDistinct({ cardId: loveNotifications.cardId })
      .from(loveNotifications)
      .where(and(isNull(loveNotifications.pushedAt), isNull(loveNotifications.readAt)));
    for (const row of pending) {
      scheduleLovePush(row.cardId);
    }
  } catch (error) {
    console.error("love_push_catch_up_failed", {
      name: error instanceof Error ? error.name : "error",
    });
  }
}

/** No ids, tokens, or names: only which gate stopped the push. */
function logLovePushSkipped(reason: "throttled" | "switch_off" | "blocked" | "no_token" | "no_config"): void {
  console.log("love_push_skipped", { reason });
}
