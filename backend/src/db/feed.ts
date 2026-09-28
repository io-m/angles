import { and, arrayOverlaps, asc, desc, eq, inArray, sql, type SQL } from "drizzle-orm";
import { getOwnerUserId } from "../lib/authStub.js";
import { rankCards, spreadRanked, type ViewerAffinity } from "../lib/feedRanking.js";
import type {
  Category,
  Emotion,
  FeedCursor,
  FeedListQuery,
  FeedSessionCursor,
  StoredCard,
  Style,
} from "../types/index.js";
import { DbError, getDb, wrapDbError } from "./client.js";
import {
  lockUserPair,
  notBlockedBetween,
  notReportedBy,
  usersAreBlocked,
} from "./communitySafety.js";
import { newerThanCursor, olderThanCursor } from "./cursor.js";
import { followedAuthorIds } from "./follows.js";
import { loadCardHeartTotals } from "./hearts.js";
import { storedCardsForViewer, type CardLoaded } from "./mapCard.js";
import { cardReframes, cards, savedAngles } from "./schema.js";

type Queryable = { query: ReturnType<typeof getDb>["query"] };

async function loadFeedCardRow(
  db: Queryable,
  id: string,
  viewerId: string,
): Promise<CardLoaded | null> {
  const row = await db.query.cards.findFirst({
    where: and(
      eq(cards.id, id),
      notBlockedBetween(viewerId, cards.userId),
      notReportedBy(viewerId, cards.id),
    ),
    with: {
      user: true,
      reframes: { orderBy: [asc(cardReframes.position)] },
      cardTags: { with: { tag: true } },
    },
  });
  return row ?? null;
}

function isFeedSaveTarget(row: CardLoaded, viewerId: string): boolean {
  return row.isPublic && row.userId !== viewerId;
}

function styleExistsFilter(db: ReturnType<typeof getDb>, style: Style) {
  return inArray(
    cards.id,
    db.select({ id: cardReframes.cardId }).from(cardReframes).where(eq(cardReframes.style, style)),
  );
}

/** Everything but paging: public, visible to this viewer, and inside the facets. */
function feedFilters(
  db: ReturnType<typeof getDb>,
  viewerId: string,
  query: FeedListQuery,
): SQL[] {
  // A literal, not a bound parameter, so even a generic plan can prove the partial index applies.
  const filters: SQL[] = [
    sql`${cards.isPublic} = true`,
    notBlockedBetween(viewerId, cards.userId),
    notReportedBy(viewerId, cards.id),
  ];
  if (query.categories?.length) {
    filters.push(inArray(cards.category, query.categories) as SQL);
  }
  if (query.emotions?.length) {
    filters.push(arrayOverlaps(cards.emotions, query.emotions) as SQL);
  }
  if (query.style) {
    filters.push(styleExistsFilter(db, query.style) as SQL);
  }
  return filters;
}

export async function listFeed(query: FeedListQuery): Promise<StoredCard[]> {
  try {
    const viewerId = getOwnerUserId();
    const db = getDb();
    const filters = feedFilters(db, viewerId, query);
    if (query.before) {
      filters.push(olderThanCursor(query.before));
    }
    if (query.after) {
      filters.push(newerThanCursor(query.after));
    }

    const rows = await db.query.cards.findMany({
      where: and(...filters),
      orderBy: [desc(cards.createdAt), desc(cards.id)],
      limit: query.limit,
      with: {
        user: true,
        reframes: { orderBy: [asc(cardReframes.position)] },
        cardTags: { with: { tag: true } },
      },
    });

    return storedCardsForViewer(rows, viewerId);
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "listFeed");
  }
}

/** Cards scored before paging. Bounded so one request cannot rank the whole catalog. */
const RANKING_CANDIDATE_CAP = 1000;

/**
 * Resonance-ranked page.
 *
 * The candidate set is frozen at `session.startedAt`, which is what makes offset paging
 * exact: nothing can join the set mid-scroll, so a page can neither repeat a card nor
 * skip one. Posts newer than that are arrivals and come back through `after` instead.
 *
 * Above `RANKING_CANDIDATE_CAP` the oldest cards stop being reachable by ranking. Add a
 * sampled tail to the candidate query before the public catalog gets that large.
 */
export async function listRankedFeed(
  query: FeedListQuery & { session: FeedSessionCursor },
): Promise<StoredCard[]> {
  try {
    const viewerId = getOwnerUserId();
    const db = getDb();
    const filters = feedFilters(db, viewerId, query);
    filters.push(sql`${cards.createdAt} <= ${query.session.startedAt.toISOString()}::timestamptz`);

    const candidates = await db
      .select({
        id: cards.id,
        authorId: cards.userId,
        createdAt: cards.createdAt,
        category: cards.category,
        emotions: cards.emotions,
        intensity: cards.intensity,
        spotlightStyle: cards.spotlightStyle,
      })
      .from(cards)
      .where(and(...filters))
      .orderBy(desc(cards.createdAt), desc(cards.id))
      .limit(RANKING_CANDIDATE_CAP);

    if (candidates.length === 0) {
      return [];
    }

    const ids = candidates.map((row) => row.id);
    const [hearts, followed, affinity] = await Promise.all([
      loadCardHeartTotals(ids, db),
      followedAuthorIds(
        viewerId,
        candidates.map((row) => row.authorId),
        db,
      ),
      loadViewerAffinity(viewerId, db),
    ]);

    const now = new Date();
    const ranked = rankCards(
      candidates.map((row) => ({
        id: row.id,
        authorId: row.authorId,
        createdAt: row.createdAt,
        category: row.category,
        emotions: row.emotions,
        hearts: hearts.get(row.id) ?? 0,
        followed: followed.has(row.authorId),
      })),
      { now, seed: query.session.seed, affinity },
    );

    const byId = new Map(candidates.map((row) => [row.id, row]));
    const spread = spreadRanked(
      ranked.flatMap((scored) => {
        const row = byId.get(scored.id);
        return row ? [row] : [];
      }),
      query.limit,
    );

    const pageIds = spread
      .slice(query.session.offset, query.session.offset + query.limit)
      .map((row) => row.id);
    if (pageIds.length === 0) {
      return [];
    }

    const rows = await db.query.cards.findMany({
      where: inArray(cards.id, pageIds),
      with: {
        user: true,
        reframes: { orderBy: [asc(cardReframes.position)] },
        cardTags: { with: { tag: true } },
      },
    });
    const loaded = new Map(rows.map((row) => [row.id, row]));
    const ordered = pageIds.flatMap((id) => {
      const row = loaded.get(id);
      return row ? [row] : [];
    });

    return storedCardsForViewer(ordered, viewerId);
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "listRankedFeed");
  }
}

/**
 * What the viewer has been writing about lately, from their own cards. This is the
 * recognition term: the reason their feed should not read like a stranger's.
 */
async function loadViewerAffinity(
  viewerId: string,
  db: ReturnType<typeof getDb>,
): Promise<ViewerAffinity> {
  const recent = await db
    .select({ category: cards.category, emotions: cards.emotions })
    .from(cards)
    .where(eq(cards.userId, viewerId))
    .orderBy(desc(cards.createdAt), desc(cards.id))
    .limit(AFFINITY_SAMPLE);

  const categoryCounts = new Map<Category, number>();
  const emotionCounts = new Map<Emotion, number>();
  for (const row of recent) {
    categoryCounts.set(row.category, (categoryCounts.get(row.category) ?? 0) + 1);
    for (const emotion of row.emotions) {
      emotionCounts.set(emotion, (emotionCounts.get(emotion) ?? 0) + 1);
    }
  }

  return {
    categories: new Set(topKeys(categoryCounts, AFFINITY_CATEGORIES)),
    emotions: new Set(topKeys(emotionCounts, AFFINITY_EMOTIONS)),
  };
}

/** Own cards read for affinity, and how many of each facet survive. */
const AFFINITY_SAMPLE = 30;
const AFFINITY_CATEGORIES = 3;
const AFFINITY_EMOTIONS = 5;

function topKeys<T>(counts: Map<T, number>, keep: number): T[] {
  return [...counts.entries()]
    .sort((left, right) => right[1] - left[1])
    .slice(0, keep)
    .map(([key]) => key);
}

/** One author's published cards. Private cards stay out, including their own. */
export async function listPublicCardsForUser(query: {
  userId: string;
  limit: number;
  before?: FeedCursor;
}): Promise<StoredCard[]> {
  try {
    const viewerId = getOwnerUserId();
    const db = getDb();
    const filters = [
      eq(cards.userId, query.userId),
      eq(cards.isPublic, true),
      notBlockedBetween(viewerId, cards.userId),
      notReportedBy(viewerId, cards.id),
    ];
    if (query.before) {
      filters.push(olderThanCursor(query.before));
    }

    const rows = await db.query.cards.findMany({
      where: and(...filters),
      orderBy: [desc(cards.createdAt), desc(cards.id)],
      limit: query.limit,
      with: {
        user: true,
        reframes: { orderBy: [asc(cardReframes.position)] },
        cardTags: { with: { tag: true } },
      },
    });

    return storedCardsForViewer(rows, viewerId);
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "listPublicCardsForUser");
  }
}

/** Public cards cooked by one model. Private cards stay out. */
export async function listPublicCardsForModel(query: {
  model: string;
  limit: number;
  before?: FeedCursor;
}): Promise<StoredCard[]> {
  try {
    const viewerId = getOwnerUserId();
    const db = getDb();
    const filters = [
      eq(cards.model, query.model),
      sql`${cards.isPublic} = true`,
      notBlockedBetween(viewerId, cards.userId),
      notReportedBy(viewerId, cards.id),
    ];
    if (query.before) {
      filters.push(olderThanCursor(query.before));
    }

    const rows = await db.query.cards.findMany({
      where: and(...filters),
      orderBy: [desc(cards.createdAt), desc(cards.id)],
      limit: query.limit,
      with: {
        user: true,
        reframes: { orderBy: [asc(cardReframes.position)] },
        cardTags: { with: { tag: true } },
      },
    });

    return storedCardsForViewer(rows, viewerId);
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "listPublicCardsForModel");
  }
}

export type FeedSaveResult =
  | { ok: true; card: StoredCard }
  | { ok: false; reason: "not_found" | "unknown_style" };

type AppTx = Parameters<Parameters<ReturnType<typeof getDb>["transaction"]>[0]>[0];

async function withFeedTarget(
  id: string,
  mutate: (tx: AppTx, row: CardLoaded, viewerId: string) => Promise<FeedSaveResult>,
): Promise<FeedSaveResult> {
  try {
    return await getDb().transaction(async (tx) => {
      const viewerId = getOwnerUserId();
      const [target] = await tx
        .select({ authorId: cards.userId })
        .from(cards)
        .where(eq(cards.id, id))
        .limit(1);
      if (!target || target.authorId === viewerId) {
        return { ok: false, reason: "not_found" };
      }
      await lockUserPair(tx, viewerId, target.authorId);
      const [locked] = await tx
        .select({ authorId: cards.userId, isPublic: cards.isPublic })
        .from(cards)
        .where(eq(cards.id, id))
        .for("update");
      if (
        !locked ||
        !locked.isPublic ||
        locked.authorId !== target.authorId ||
        (await usersAreBlocked(viewerId, locked.authorId, tx))
      ) {
        return { ok: false, reason: "not_found" };
      }
      const row = await loadFeedCardRow(tx, id, viewerId);
      if (!row || !isFeedSaveTarget(row, viewerId)) {
        return { ok: false, reason: "not_found" };
      }
      return mutate(tx, row, viewerId);
    });
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "feedSave");
  }
}

async function returnViewerCard(
  db: Queryable & Pick<ReturnType<typeof getDb>, "select">,
  id: string,
  viewerId: string,
): Promise<FeedSaveResult> {
  const row = await loadFeedCardRow(db, id, viewerId);
  if (!row) {
    return { ok: false, reason: "not_found" };
  }
  const [card] = await storedCardsForViewer([row], viewerId, db);
  if (!card) {
    return { ok: false, reason: "not_found" };
  }
  return { ok: true, card };
}

export async function saveFeedAngle(id: string, style: Style): Promise<FeedSaveResult> {
  return withFeedTarget(id, async (tx, row, viewerId) => {
    if (!row.reframes.some((item) => item.style === style)) {
      return { ok: false, reason: "unknown_style" };
    }
    await tx
      .insert(savedAngles)
      .values({ userId: viewerId, cardId: id, style, favoritedAt: new Date() })
      .onConflictDoUpdate({
        target: [savedAngles.userId, savedAngles.cardId, savedAngles.style],
        set: { favoritedAt: new Date() },
      });
    return returnViewerCard(tx, id, viewerId);
  });
}

export async function unsaveFeedAngle(id: string, style: Style): Promise<FeedSaveResult> {
  return withFeedTarget(id, async (tx, row, viewerId) => {
    if (!row.reframes.some((item) => item.style === style)) {
      return { ok: false, reason: "unknown_style" };
    }
    await tx
      .delete(savedAngles)
      .where(
        and(eq(savedAngles.userId, viewerId), eq(savedAngles.cardId, id), eq(savedAngles.style, style)),
      );
    return returnViewerCard(tx, id, viewerId);
  });
}

/** Works on any card the viewer saved, so a card that went private can still leave their library. */
export async function clearFeedSaves(id: string): Promise<{ ok: boolean }> {
  try {
    const viewerId = getOwnerUserId();
    return await getDb().transaction(async (tx) => {
      const [target] = await tx
        .select({ authorId: cards.userId })
        .from(cards)
        .where(eq(cards.id, id))
        .limit(1);
      if (!target || target.authorId === viewerId) {
        return { ok: false };
      }
      await lockUserPair(tx, viewerId, target.authorId);
      const removed = await tx
        .delete(savedAngles)
        .where(and(eq(savedAngles.userId, viewerId), eq(savedAngles.cardId, id)))
        .returning({ cardId: savedAngles.cardId });
      if (removed.length > 0) {
        return { ok: true };
      }
      const row = await loadFeedCardRow(tx, id, viewerId);
      return { ok: row !== null && isFeedSaveTarget(row, viewerId) };
    });
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "clearFeedSaves");
  }
}
