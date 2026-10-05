import { and, asc, eq, inArray, isNull, sql } from "drizzle-orm";
import type { ReportReason } from "../lib/communitySafetyTypes.js";
import type { Style } from "../types/index.js";
import { getDb } from "./client.js";
import { cardReframes, cardReports, cards, users } from "./schema.js";

/**
 * The operator side of community reports. `pnpm reports` and `/admin` both call these
 * functions. Hide, keep, delete, suspend, and unsuspend stay here so the CLI and the
 * site cannot drift.
 */
export type PendingReportedCard = {
  cardId: string;
  authorId: string;
  authorInitials: string;
  authorSuspended: boolean;
  isPublic: boolean;
  firstReportedAt: Date;
  reasons: Partial<Record<ReportReason, number>>;
  reportCount: number;
  thought: string;
  reframes: { style: Style; reframe: string }[];
};

type Db = ReturnType<typeof getDb>;

/** Cards with at least one unreviewed report, oldest report first. */
export async function listPendingReports(
  limit = 50,
  db: Db = getDb(),
): Promise<PendingReportedCard[]> {
  const pending = await db
    .select({
      cardId: cardReports.cardId,
      reason: cardReports.reason,
      createdAt: cardReports.createdAt,
    })
    .from(cardReports)
    .where(isNull(cardReports.reviewedAt))
    .orderBy(asc(cardReports.createdAt));

  const byCard = new Map<string, { first: Date; reasons: Partial<Record<ReportReason, number>>; count: number }>();
  for (const row of pending) {
    const entry = byCard.get(row.cardId) ?? { first: row.createdAt, reasons: {}, count: 0 };
    entry.reasons[row.reason] = (entry.reasons[row.reason] ?? 0) + 1;
    entry.count += 1;
    byCard.set(row.cardId, entry);
  }
  const cardIds = [...byCard.keys()].slice(0, limit);
  if (cardIds.length === 0) {
    return [];
  }

  const rows = await db
    .select({
      id: cards.id,
      userId: cards.userId,
      isPublic: cards.isPublic,
      thought: cards.thoughtEn,
      initials: users.initials,
      suspendedAt: users.publishingSuspendedAt,
    })
    .from(cards)
    .innerJoin(users, eq(users.id, cards.userId))
    .where(inArray(cards.id, cardIds));
  const reframes = await db
    .select({ cardId: cardReframes.cardId, style: cardReframes.style, reframe: cardReframes.reframe })
    .from(cardReframes)
    .where(inArray(cardReframes.cardId, cardIds))
    .orderBy(asc(cardReframes.position));

  const cardById = new Map(rows.map((row) => [row.id, row]));
  return cardIds.flatMap((cardId) => {
    const card = cardById.get(cardId);
    const entry = byCard.get(cardId);
    if (!card || !entry) {
      return [];
    }
    return [
      {
        cardId,
        authorId: card.userId,
        authorInitials: card.initials,
        authorSuspended: card.suspendedAt !== null,
        isPublic: card.isPublic,
        firstReportedAt: entry.first,
        reasons: entry.reasons,
        reportCount: entry.count,
        thought: card.thought,
        reframes: reframes
          .filter((item) => item.cardId === cardId)
          .map(({ style, reframe }) => ({ style, reframe })),
      },
    ];
  });
}

/**
 * `hidden` makes the card private and keeps it from being published again. `kept` dismisses
 * the open reports, so they stop counting toward the automatic threshold; it never republishes
 * a card the threshold made private (the author can, through moderation).
 */
export async function resolveCardReports(
  cardId: string,
  resolution: "kept" | "hidden",
  now: Date = new Date(),
  db: Db = getDb(),
): Promise<"ok" | "not_found"> {
  return db.transaction(async (tx) => {
    const [card] = await tx
      .select({ id: cards.id })
      .from(cards)
      .where(eq(cards.id, cardId))
      .for("update");
    if (!card) {
      return "not_found";
    }
    if (resolution === "hidden") {
      await tx.update(cards).set({ isPublic: false }).where(eq(cards.id, cardId));
    }
    await tx
      .update(cardReports)
      .set({ reviewedAt: now, resolution })
      .where(and(eq(cardReports.cardId, cardId), isNull(cardReports.reviewedAt)));
    return "ok";
  });
}

export async function deleteReportedCard(cardId: string, db: Db = getDb()): Promise<boolean> {
  const deleted = await db.delete(cards).where(eq(cards.id, cardId)).returning({ id: cards.id });
  return deleted.length > 0;
}

/**
 * Stops an account publishing: every card goes private and open reports on them are upheld.
 * The account keeps its private library and subscription.
 */
export async function suspendPublishing(
  userId: string,
  now: Date = new Date(),
  db: Db = getDb(),
): Promise<"ok" | "not_found"> {
  return db.transaction(async (tx) => {
    const [user] = await tx
      .update(users)
      .set({ publishingSuspendedAt: now, updatedAt: now })
      .where(eq(users.id, userId))
      .returning({ id: users.id });
    if (!user) {
      return "not_found";
    }
    await tx.update(cards).set({ isPublic: false }).where(eq(cards.userId, userId));
    const owned = tx.select({ id: cards.id }).from(cards).where(eq(cards.userId, userId));
    await tx
      .update(cardReports)
      .set({ reviewedAt: now, resolution: "hidden" })
      .where(and(inArray(cardReports.cardId, owned), isNull(cardReports.reviewedAt)));
    return "ok";
  });
}

/** Lets the account publish again. Its cards stay private until the author posts them. */
export async function restorePublishing(
  userId: string,
  now: Date = new Date(),
  db: Db = getDb(),
): Promise<"ok" | "not_found"> {
  const [user] = await db
    .update(users)
    .set({ publishingSuspendedAt: null, updatedAt: now })
    .where(eq(users.id, userId))
    .returning({ id: users.id });
  return user ? "ok" : "not_found";
}

export type CardReview = {
  cardId: string;
  authorId: string;
  authorInitials: string;
  authorEmail: string;
  authorSuspended: boolean;
  isPublic: boolean;
  reportCount: number;
  reasons: Partial<Record<ReportReason, number>>;
  firstReportedAt: Date | null;
  thought: string;
  reframes: { style: Style; reframe: string }[];
};

/** One card for the operator, including a card that has no open reports. */
export async function getCardReview(cardId: string, db: Db = getDb()): Promise<CardReview | null> {
  const [card] = await db
    .select({
      id: cards.id,
      userId: cards.userId,
      isPublic: cards.isPublic,
      thought: cards.thoughtEn,
      initials: users.initials,
      email: users.email,
      suspendedAt: users.publishingSuspendedAt,
    })
    .from(cards)
    .innerJoin(users, eq(users.id, cards.userId))
    .where(eq(cards.id, cardId));
  if (!card) {
    return null;
  }

  const reports = await db
    .select({ reason: cardReports.reason, createdAt: cardReports.createdAt })
    .from(cardReports)
    .where(and(eq(cardReports.cardId, cardId), isNull(cardReports.reviewedAt)))
    .orderBy(asc(cardReports.createdAt));
  const reframes = await db
    .select({ style: cardReframes.style, reframe: cardReframes.reframe })
    .from(cardReframes)
    .where(eq(cardReframes.cardId, cardId))
    .orderBy(asc(cardReframes.position));

  const reasons: Partial<Record<ReportReason, number>> = {};
  for (const row of reports) {
    reasons[row.reason] = (reasons[row.reason] ?? 0) + 1;
  }

  return {
    cardId: card.id,
    authorId: card.userId,
    authorInitials: card.initials,
    authorEmail: card.email,
    authorSuspended: card.suspendedAt !== null,
    isPublic: card.isPublic,
    reportCount: reports.length,
    reasons,
    firstReportedAt: reports[0]?.createdAt ?? null,
    thought: card.thought,
    reframes,
  };
}

export type AuthorReview = {
  userId: string;
  email: string;
  initials: string;
  publishingSuspended: boolean;
  publicCardCount: number;
};

export async function getAuthorReview(userId: string, db: Db = getDb()): Promise<AuthorReview | null> {
  const [user] = await db
    .select({
      id: users.id,
      email: users.email,
      initials: users.initials,
      suspendedAt: users.publishingSuspendedAt,
    })
    .from(users)
    .where(eq(users.id, userId));
  if (!user) {
    return null;
  }

  const [countRow] = await db
    .select({ count: sql<number>`count(*)::int` })
    .from(cards)
    .where(and(eq(cards.userId, userId), eq(cards.isPublic, true)));

  return {
    userId: user.id,
    email: user.email,
    initials: user.initials,
    publishingSuspended: user.suspendedAt !== null,
    publicCardCount: countRow?.count ?? 0,
  };
}
