import { and, count, eq, isNull } from "drizzle-orm";
import { getDb } from "./client.js";
import { notBlockedBetween } from "./communitySafety.js";
import { followNotifications, loveNotifications } from "./schema.js";

type Selectable = Pick<ReturnType<typeof getDb>, "select">;

/** Unread follows the bell can show. */
export async function unreadFollowCount(recipientId: string, db: Selectable = getDb()): Promise<number> {
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

/** Unread loves the bell can show. */
export async function unreadLoveCount(recipientId: string, db: Selectable = getDb()): Promise<number> {
  const [unread] = await db
    .select({ value: count() })
    .from(loveNotifications)
    .where(
      and(
        eq(loveNotifications.recipientId, recipientId),
        isNull(loveNotifications.readAt),
        notBlockedBetween(recipientId, loveNotifications.actorId),
      ),
    );
  return Number(unread?.value ?? 0);
}

/** The badge number: everything unread the bell can show, follows and loves together. */
export async function unreadNotificationCount(
  recipientId: string,
  db: Selectable = getDb(),
): Promise<number> {
  const [follows, loves] = await Promise.all([
    unreadFollowCount(recipientId, db),
    unreadLoveCount(recipientId, db),
  ]);
  return follows + loves;
}
