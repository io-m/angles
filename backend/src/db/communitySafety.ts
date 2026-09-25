import { and, count, desc, eq, inArray, or, sql, type SQL } from "drizzle-orm";
import type { AnyPgColumn } from "drizzle-orm/pg-core";
import { getOwnerUserId } from "../lib/authStub.js";
import { avatarUrlFor } from "../lib/avatarUrl.js";
import type { ReportReason } from "../lib/communitySafetyTypes.js";
import type { StoredCardAuthor } from "../types/index.js";
import { DbError, getDb, wrapDbError } from "./client.js";
import { cardReports, cards, follows, savedAngles, userBlocks, users } from "./schema.js";

type Selectable = Pick<ReturnType<typeof getDb>, "select">;
export type AppTransaction = Parameters<
  Parameters<ReturnType<typeof getDb>["transaction"]>[0]
>[0];

export async function lockUserPair(
  tx: AppTransaction,
  firstUserId: string,
  secondUserId: string,
): Promise<void> {
  const [first, second] = [firstUserId.toLowerCase(), secondUserId.toLowerCase()].sort();
  await tx.execute(
    sql`select pg_advisory_xact_lock(
      hashtextextended(${`social-pair:${first}:${second}`}, 0)
    )`,
  );
}

export function notBlockedBetween(viewerId: string, authorId: AnyPgColumn): SQL {
  return sql`not exists (
    select 1 from "user_blocks"
    where ("user_blocks"."blocker_id" = ${viewerId} and "user_blocks"."blocked_id" = ${authorId})
       or ("user_blocks"."blocker_id" = ${authorId} and "user_blocks"."blocked_id" = ${viewerId})
  )`;
}

export function notReportedBy(viewerId: string, cardId: AnyPgColumn): SQL {
  return sql`not exists (
    select 1 from "card_reports"
    where "card_reports"."reporter_id" = ${viewerId}
      and "card_reports"."card_id" = ${cardId}
  )`;
}

export async function usersAreBlocked(
  firstUserId: string,
  secondUserId: string,
  db: Selectable = getDb(),
): Promise<boolean> {
  if (firstUserId === secondUserId) {
    return false;
  }
  try {
    const rows = await db
      .select({ blockerId: userBlocks.blockerId })
      .from(userBlocks)
      .where(
        or(
          and(eq(userBlocks.blockerId, firstUserId), eq(userBlocks.blockedId, secondUserId)),
          and(eq(userBlocks.blockerId, secondUserId), eq(userBlocks.blockedId, firstUserId)),
        ),
      )
      .limit(1);
    return rows.length > 0;
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "usersAreBlocked");
  }
}

export type BlockWriteResult = "ok" | "not_found" | "self";

export async function blockUser(blockedId: string): Promise<BlockWriteResult> {
  const blockerId = getOwnerUserId();
  if (blockedId === blockerId) {
    return "self";
  }
  try {
    return await getDb().transaction(async (tx) => {
      await lockUserPair(tx, blockerId, blockedId);
      const target = await tx.query.users.findFirst({
        where: eq(users.id, blockedId),
        columns: { id: true },
      });
      if (!target) {
        return "not_found";
      }

      await tx.insert(userBlocks).values({ blockerId, blockedId }).onConflictDoNothing();
      await tx
        .delete(follows)
        .where(
          or(
            and(eq(follows.followerId, blockerId), eq(follows.followeeId, blockedId)),
            and(eq(follows.followerId, blockedId), eq(follows.followeeId, blockerId)),
          ),
        );

      const blockerCards = tx.select({ id: cards.id }).from(cards).where(eq(cards.userId, blockerId));
      const blockedCards = tx.select({ id: cards.id }).from(cards).where(eq(cards.userId, blockedId));
      await tx
        .delete(savedAngles)
        .where(
          or(
            and(eq(savedAngles.userId, blockerId), inArray(savedAngles.cardId, blockedCards)),
            and(eq(savedAngles.userId, blockedId), inArray(savedAngles.cardId, blockerCards)),
          ),
        );
      return "ok";
    });
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "blockUser");
  }
}

export async function unblockUser(blockedId: string): Promise<BlockWriteResult> {
  const blockerId = getOwnerUserId();
  if (blockedId === blockerId) {
    return "self";
  }
  try {
    return await getDb().transaction(async (tx) => {
      await lockUserPair(tx, blockerId, blockedId);
      const target = await tx.query.users.findFirst({
        where: eq(users.id, blockedId),
        columns: { id: true },
      });
      if (!target) {
        return "not_found";
      }
      await tx
        .delete(userBlocks)
        .where(and(eq(userBlocks.blockerId, blockerId), eq(userBlocks.blockedId, blockedId)));
      return "ok";
    });
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "unblockUser");
  }
}

export async function listBlockedUsers(): Promise<StoredCardAuthor[]> {
  const blockerId = getOwnerUserId();
  try {
    const rows = await getDb()
      .select({
        id: users.id,
        initials: users.initials,
        avatarKey: users.avatarKey,
      })
      .from(userBlocks)
      .innerJoin(users, eq(users.id, userBlocks.blockedId))
      .where(eq(userBlocks.blockerId, blockerId))
      .orderBy(desc(userBlocks.createdAt), desc(users.id));

    return rows.map((row) => {
      const user: StoredCardAuthor = { id: row.id, initials: row.initials, following: false };
      const avatarUrl = avatarUrlFor(row.id, row.avatarKey);
      if (avatarUrl) {
        user.avatarUrl = avatarUrl;
      }
      return user;
    });
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "listBlockedUsers");
  }
}

export type ReportCardResult =
  | { ok: true; created: boolean }
  | { ok: false; reason: "not_found" | "own_card" | "private_card" };

export async function reportCard(cardId: string, reason: ReportReason): Promise<ReportCardResult> {
  const reporterId = getOwnerUserId();
  try {
    return await getDb().transaction(async (tx) => {
      const [card] = await tx
        .select({ id: cards.id, userId: cards.userId, isPublic: cards.isPublic })
        .from(cards)
        .where(eq(cards.id, cardId))
        .for("update");
      if (!card) {
        return { ok: false, reason: "not_found" };
      }
      if (card.userId === reporterId) {
        return { ok: false, reason: "own_card" };
      }

      const [existing] = await tx
        .select({ cardId: cardReports.cardId })
        .from(cardReports)
        .where(and(eq(cardReports.reporterId, reporterId), eq(cardReports.cardId, cardId)))
        .limit(1);
      if (existing) {
        return { ok: true, created: false };
      }
      if (!card.isPublic || (await usersAreBlocked(reporterId, card.userId, tx))) {
        return { ok: false, reason: card.isPublic ? "not_found" : "private_card" };
      }

      await tx.insert(cardReports).values({ reporterId, cardId, reason });
      await tx
        .delete(savedAngles)
        .where(and(eq(savedAngles.userId, reporterId), eq(savedAngles.cardId, cardId)));

      const [total] = await tx
        .select({ value: count() })
        .from(cardReports)
        .where(eq(cardReports.cardId, cardId));
      if ((total?.value ?? 0) >= 3) {
        await tx.update(cards).set({ isPublic: false }).where(eq(cards.id, cardId));
      }
      return { ok: true, created: true };
    });
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "reportCard");
  }
}
