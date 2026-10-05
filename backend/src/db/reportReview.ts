import { and, asc, desc, eq, ilike, inArray, isNotNull, isNull, or, sql } from "drizzle-orm";
import { REPORT_REASONS, type ReportReason, type ReportResolution } from "../lib/communitySafetyTypes.js";
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

const EXCERPT_LENGTH = 140;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** One line for a list. The full thought stays on the card detail. */
export function thoughtExcerpt(thought: string, max = EXCERPT_LENGTH): string {
  const flat = thought.trim().replace(/\s+/g, " ");
  if (flat.length <= max) {
    return flat;
  }
  return `${flat.slice(0, max - 1).trimEnd()}…`;
}

export type ReportDashboard = {
  openCount: number;
  privateCount: number;
  suspendedAuthorCount: number;
  reviewedCount: number;
  reasons: Record<ReportReason, number>;
};

/** Counts for the overview. A card with two reasons increments both reason tiles. */
export async function summarizeReports(db: Db = getDb()): Promise<ReportDashboard> {
  const pending = await db
    .select({
      cardId: cardReports.cardId,
      reason: cardReports.reason,
      isPublic: cards.isPublic,
      authorId: cards.userId,
      suspendedAt: users.publishingSuspendedAt,
    })
    .from(cardReports)
    .innerJoin(cards, eq(cards.id, cardReports.cardId))
    .innerJoin(users, eq(users.id, cards.userId))
    .where(isNull(cardReports.reviewedAt));

  const open = new Map<
    string,
    { reasons: Set<ReportReason>; isPublic: boolean; authorId: string; suspended: boolean }
  >();
  for (const row of pending) {
    const entry = open.get(row.cardId) ?? {
      reasons: new Set<ReportReason>(),
      isPublic: row.isPublic,
      authorId: row.authorId,
      suspended: row.suspendedAt !== null,
    };
    entry.reasons.add(row.reason);
    open.set(row.cardId, entry);
  }

  const reasons = Object.fromEntries(REPORT_REASONS.map((reason) => [reason, 0])) as Record<ReportReason, number>;
  const suspendedAuthors = new Set<string>();
  let privateCount = 0;
  for (const entry of open.values()) {
    if (!entry.isPublic) {
      privateCount += 1;
    }
    if (entry.suspended) {
      suspendedAuthors.add(entry.authorId);
    }
    for (const reason of entry.reasons) {
      reasons[reason] += 1;
    }
  }

  const [reviewed] = await db
    .select({ count: sql<number>`count(distinct ${cardReports.cardId})::int` })
    .from(cardReports)
    .innerJoin(cards, eq(cards.id, cardReports.cardId))
    .where(isNotNull(cardReports.reviewedAt));

  return {
    openCount: open.size,
    privateCount,
    suspendedAuthorCount: suspendedAuthors.size,
    reviewedCount: reviewed?.count ?? 0,
    reasons,
  };
}

export type ReviewedCard = {
  cardId: string;
  authorId: string;
  authorInitials: string;
  authorSuspended: boolean;
  isPublic: boolean;
  thought: string;
  resolution: ReportResolution;
  reviewedAt: Date;
  reasons: Partial<Record<ReportReason, number>>;
};

/** Latest decision per card, newest first. A deleted card is already gone. */
export async function listReviewedReports(limit = 50, db: Db = getDb()): Promise<ReviewedCard[]> {
  const rows = await db
    .select({
      cardId: cardReports.cardId,
      reason: cardReports.reason,
      resolution: cardReports.resolution,
      reviewedAt: cardReports.reviewedAt,
      thought: cards.thoughtEn,
      isPublic: cards.isPublic,
      authorId: cards.userId,
      initials: users.initials,
      suspendedAt: users.publishingSuspendedAt,
    })
    .from(cardReports)
    .innerJoin(cards, eq(cards.id, cardReports.cardId))
    .innerJoin(users, eq(users.id, cards.userId))
    .where(isNotNull(cardReports.reviewedAt))
    .orderBy(desc(cardReports.reviewedAt));

  const byCard = new Map<string, ReviewedCard>();
  for (const row of rows) {
    if (!row.reviewedAt || !row.resolution) {
      continue;
    }
    const existing = byCard.get(row.cardId);
    if (!existing) {
      byCard.set(row.cardId, {
        cardId: row.cardId,
        authorId: row.authorId,
        authorInitials: row.initials,
        authorSuspended: row.suspendedAt !== null,
        isPublic: row.isPublic,
        thought: row.thought,
        resolution: row.resolution,
        reviewedAt: row.reviewedAt,
        reasons: { [row.reason]: 1 },
      });
      continue;
    }
    existing.reasons[row.reason] = (existing.reasons[row.reason] ?? 0) + 1;
  }
  return [...byCard.values()].slice(0, limit);
}

export type AuthorPublicCard = {
  cardId: string;
  thought: string;
  createdAt: Date;
};

export async function listAuthorPublicCards(
  userId: string,
  limit = 20,
  db: Db = getDb(),
): Promise<AuthorPublicCard[]> {
  const rows = await db
    .select({ id: cards.id, thought: cards.thoughtEn, createdAt: cards.createdAt })
    .from(cards)
    .where(and(eq(cards.userId, userId), eq(cards.isPublic, true)))
    .orderBy(desc(cards.createdAt))
    .limit(limit);
  return rows.map((row) => ({ cardId: row.id, thought: row.thought, createdAt: row.createdAt }));
}

export type AdminSearchCard = {
  cardId: string;
  thought: string;
  isPublic: boolean;
  authorId: string;
  authorInitials: string;
  authorEmail: string;
  authorSuspended: boolean;
  reportCount: number;
  reasons: Partial<Record<ReportReason, number>>;
};

export type AdminSearchResult = {
  cards: AdminSearchCard[];
  users: AuthorReview[];
};

/** A UUID opens that card and/or user. Other text matches the thought and the account email. */
export async function searchAdmin(raw: string, db: Db = getDb()): Promise<AdminSearchResult> {
  const query = raw.trim();
  if (UUID.test(query)) {
    const [card, author] = await Promise.all([getCardReview(query, db), getAuthorReview(query, db)]);
    return {
      cards: card ? [searchCardFromReview(card)] : [],
      users: author ? [author] : [],
    };
  }

  const needle = query.replace(/[%_\\]/g, "").slice(0, 80);
  if (needle.length < 2) {
    return { cards: [], users: [] };
  }
  const pattern = `%${needle}%`;
  const cardRows = await db
    .select({
      id: cards.id,
      thought: cards.thoughtEn,
      isPublic: cards.isPublic,
      authorId: cards.userId,
      initials: users.initials,
      email: users.email,
      suspendedAt: users.publishingSuspendedAt,
    })
    .from(cards)
    .innerJoin(users, eq(users.id, cards.userId))
    .where(or(ilike(cards.thoughtEn, pattern), ilike(users.email, pattern)))
    .orderBy(desc(cards.createdAt))
    .limit(25);
  const userRows = await db
    .select({
      id: users.id,
      email: users.email,
      initials: users.initials,
      suspendedAt: users.publishingSuspendedAt,
    })
    .from(users)
    .where(ilike(users.email, pattern))
    .limit(25);

  const cardIds = cardRows.map((row) => row.id);
  const userIds = userRows.map((row) => row.id);
  const openReports = cardIds.length
    ? await db
        .select({ cardId: cardReports.cardId, reason: cardReports.reason })
        .from(cardReports)
        .where(and(inArray(cardReports.cardId, cardIds), isNull(cardReports.reviewedAt)))
    : [];
  const publicCounts = userIds.length
    ? await db
        .select({ userId: cards.userId, count: sql<number>`count(*)::int` })
        .from(cards)
        .where(and(inArray(cards.userId, userIds), eq(cards.isPublic, true)))
        .groupBy(cards.userId)
    : [];
  const countByUser = new Map(publicCounts.map((row) => [row.userId, row.count]));
  const reasonsByCard = new Map<string, Partial<Record<ReportReason, number>>>();
  for (const report of openReports) {
    const reasons = reasonsByCard.get(report.cardId) ?? {};
    reasons[report.reason] = (reasons[report.reason] ?? 0) + 1;
    reasonsByCard.set(report.cardId, reasons);
  }

  return {
    cards: cardRows.map((row) => {
      const reasons = reasonsByCard.get(row.id) ?? {};
      return {
        cardId: row.id,
        thought: row.thought,
        isPublic: row.isPublic,
        authorId: row.authorId,
        authorInitials: row.initials,
        authorEmail: row.email,
        authorSuspended: row.suspendedAt !== null,
        reportCount: Object.values(reasons).reduce((sum, count) => sum + (count ?? 0), 0),
        reasons,
      };
    }),
    users: userRows.map((row) => ({
      userId: row.id,
      email: row.email,
      initials: row.initials,
      publishingSuspended: row.suspendedAt !== null,
      publicCardCount: countByUser.get(row.id) ?? 0,
    })),
  };
}

function searchCardFromReview(card: CardReview): AdminSearchCard {
  return {
    cardId: card.cardId,
    thought: card.thought,
    isPublic: card.isPublic,
    authorId: card.authorId,
    authorInitials: card.authorInitials,
    authorEmail: card.authorEmail,
    authorSuspended: card.authorSuspended,
    reportCount: card.reportCount,
    reasons: card.reasons,
  };
}
