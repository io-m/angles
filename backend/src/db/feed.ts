import { and, arrayOverlaps, asc, desc, eq, inArray, isNull, lte, or, sql, type SQL } from "drizzle-orm";
import { getOwnerUserId } from "../lib/authStub.js";
import {
  assignPrimaryStyles,
  buildAffinity,
  classifyTheme,
  followMix,
  isKeptOnShelf,
  isPartlyKept,
  rankCards,
  SPREAD_LIMITS,
  spreadRanked,
  themeMix,
  type StyleTabContext,
  type StyleTabs,
  type ViewerAffinity,
} from "../lib/feedRanking.js";
import {
  STYLES,
  type Category,
  type Emotion,
  type FeedCursor,
  type FeedListQuery,
  type FeedSessionCursor,
  type StoredCard,
  type Style,
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
import { loadCardHeartTotals, loadStyleHeartCounts } from "./hearts.js";
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

export async function listFeed(
  query: FeedListQuery,
  /**
   * Arrivals under ranking: the same visibility as a ranked page, so a pull never brings
   * back a card the ranked feed hides (fully kept) or a second card of the viewer's own.
   */
  options: { rankedArrivals?: boolean } = {},
): Promise<StoredCard[]> {
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

    const found = await db.query.cards.findMany({
      where: and(...filters),
      orderBy: [desc(cards.createdAt), desc(cards.id)],
      // Read past the limit so hidden cards cannot make a full head look short: the phone
      // reads a full head of arrivals as "more may be waiting" and reloads instead.
      limit: options.rankedArrivals ? Math.min(500, query.limit * 4) : query.limit,
      with: {
        user: true,
        reframes: { orderBy: [asc(cardReframes.position)] },
        cardTags: { with: { tag: true } },
      },
    });

    if (!options.rankedArrivals) {
      return storedCardsForViewer(found, viewerId);
    }

    const kept = await loadKeptAngles(
      viewerId,
      found.map((row) => row.id),
      new Date(),
      db,
    );
    let ownShown = 0;
    const rows = found.filter((row) => {
      const styles = row.reframes.map((item) => item.style);
      if (isKeptOnShelf(kept.get(row.id), query.style, styles)) {
        return false;
      }
      if (row.userId === viewerId) {
        ownShown += 1;
        return ownShown <= SPREAD_LIMITS.own;
      }
      return true;
    });
    return storedCardsForViewer(rows.slice(0, query.limit), viewerId, db, {
      coverAvoidsKept: !query.style,
    });
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "listFeed");
  }
}

/** Cards scored before paging. Bounded so one request cannot rank the whole catalog. */
const RANKING_CANDIDATE_CAP = 1000;

const NIL_UUID = "00000000-0000-0000-0000-000000000000";

/** One ranked page, and the `createdAt|id` a pull should ask for arrivals after. */
export type RankedFeedPage = { cards: StoredCard[]; arrivalsAfter: string };

/**
 * Resonance-ranked page.
 *
 * The candidate set is frozen at `session.startedAt`, which is what makes offset paging
 * exact: nothing can join the set mid-scroll, so a page can neither repeat a card nor
 * skip one. Posts newer than that are arrivals and come back through `after` instead.
 *
 * Every ranking input is read as of `startedAt` too — hearts, follows, themes, and the
 * clock freshness is measured on — so each page of one visit is cut from the same order.
 * A heart or a follow made during the visit shapes the next one.
 *
 * Above `RANKING_CANDIDATE_CAP` the oldest cards stop being reachable by ranking. Add a
 * sampled tail to the candidate query before the public catalog gets that large.
 */
export async function listRankedFeed(
  query: FeedListQuery & { session: FeedSessionCursor },
): Promise<RankedFeedPage> {
  try {
    const viewerId = getOwnerUserId();
    const db = getDb();
    const startedAt = query.session.startedAt;
    const filters = feedFilters(db, viewerId, query);
    filters.push(sql`${cards.createdAt} <= ${startedAt.toISOString()}::timestamptz`);

    const found = await db
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

    // The newest card this visit could show. A pull asks for posts newer than this, not
    // newer than the newest card on screen: a ranked page need not hold the newest posts,
    // and everything up to here is already in this visit's order.
    const newest = found[0];
    const arrivalsAfter = newest
      ? `${newest.createdAt.toISOString()}|${newest.id}`
      : `${startedAt.toISOString()}|${NIL_UUID}`;

    // Angles the viewer already kept are not shown again, only those kept before this
    // visit began: the candidate set is frozen at `startedAt`, and a heart tapped while
    // scrolling must not make a card vanish and shift every offset after it.
    const kept = await loadKeptAngles(
      viewerId,
      found.map((row) => row.id),
      startedAt,
      db,
    );
    // For you hides a card only once every angle it has is kept, so it needs to know which
    // angles those are. A style shelf needs them for every card to pick its primary tab.
    const cardStyles = await loadCardStyles(
      query.style ? found.map((row) => row.id) : [...kept.keys()],
      db,
    );
    const candidates = found.filter(
      (row) => !isKeptOnShelf(kept.get(row.id), query.style, cardStyles.get(row.id) ?? STYLES),
    );

    if (candidates.length === 0) {
      return { cards: [], arrivalsAfter };
    }

    const now = startedAt;
    const ids = candidates.map((row) => row.id);
    const heartWindow = { before: startedAt, excludeUserId: viewerId };
    // A style shelf also needs every angle's hearts and the viewer's taste on all four
    // tabs, because a card's primary tab is decided across them.
    const [hearts, followed, affinity, angleHearts, tabs] = await Promise.all([
      loadCardHeartTotals(ids, db, heartWindow),
      followedAuthorIds(
        viewerId,
        candidates.map((row) => row.authorId),
        db,
        startedAt,
      ),
      loadViewerAffinity(viewerId, now, db),
      query.style ? loadStyleHeartCounts(ids, db, heartWindow) : Promise.resolve(null),
      query.style ? loadViewerStyleTabs(viewerId, now, db) : Promise.resolve(null),
    ]);

    const rankable = candidates.map((row) => ({
      id: row.id,
      authorId: row.authorId,
      createdAt: row.createdAt,
      category: row.category,
      emotions: row.emotions,
      hearts: hearts.get(row.id) ?? 0,
      followed: followed.has(row.authorId),
      own: row.authorId === viewerId,
      partlyKept:
        !query.style && isPartlyKept(kept.get(row.id), cardStyles.get(row.id) ?? STYLES),
      angleHeartsByStyle: Object.fromEntries(angleHearts?.get(row.id) ?? []),
      availableStyles: query.style ? cardStyles.get(row.id) : undefined,
      coverStyle: row.spotlightStyle,
    }));
    const primaryByCard =
      query.style && tabs
        ? assignPrimaryStyles(rankable, { viewerId, general: affinity, tabs })
        : undefined;
    const ranked = rankCards(rankable, {
      now,
      seed: query.session.seed,
      affinity,
      style:
        query.style && tabs
          ? {
              style: query.style,
              affinity: tabs[query.style].affinity,
              hearts: tabs[query.style].hearts,
              primaryByCard,
            }
          : undefined,
    });

    // Themes come from the general affinity on every tab: the tab's own taste only
    // reorders cards, while the mix is about what this viewer is mostly in.
    const byId = new Map(
      candidates.map((row) => [
        row.id,
        {
          ...row,
          bucket: classifyTheme(row, affinity),
          own: row.authorId === viewerId,
          followed: followed.has(row.authorId),
        },
      ]),
    );
    const spreadable = ranked.flatMap((scored) => {
      const row = byId.get(scored.id);
      return row ? [row] : [];
    });
    const spread = spreadRanked(spreadable, query.limit, {
      mix: themeMix(affinity.confidence),
      // Style shelves are about the voice; the follow floor is a For you rule.
      follow: query.style ? null : followMix(spreadable, now),
    });

    const pageIds = spread
      .slice(query.session.offset, query.session.offset + query.limit)
      .map((row) => row.id);
    if (pageIds.length === 0) {
      return { cards: [], arrivalsAfter };
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

    return {
      cards: await storedCardsForViewer(ordered, viewerId, db, { coverAvoidsKept: !query.style }),
      arrivalsAfter,
    };
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "listRankedFeed");
  }
}

/** Recent activity read per source when learning themes. */
const AFFINITY_SAMPLE = 30;

/** A heart row, reduced to what theme learning needs. */
type HeartRow = {
  cardId: string;
  style: Style;
  category: Category;
  emotions: Emotion[];
  at: Date;
};

/** The angles this viewer kept: other people's cards they hearted, and their own favorites. */
async function loadViewerHearts(
  viewerId: string,
  db: ReturnType<typeof getDb>,
  limit: number,
  /** Only hearts made by then, so a ranked visit learns the same themes on every page. */
  before: Date,
): Promise<HeartRow[]> {
  const [saved, own] = await Promise.all([
    db
      .select({
        cardId: cards.id,
        style: savedAngles.style,
        category: cards.category,
        emotions: cards.emotions,
        at: savedAngles.favoritedAt,
      })
      .from(savedAngles)
      .innerJoin(cards, eq(cards.id, savedAngles.cardId))
      .where(and(eq(savedAngles.userId, viewerId), lte(savedAngles.favoritedAt, before)))
      .orderBy(desc(savedAngles.favoritedAt), desc(cards.id))
      .limit(limit),
    db
      .select({
        cardId: cards.id,
        style: cardReframes.style,
        category: cards.category,
        emotions: cards.emotions,
        at: cardReframes.favoritedAt,
        createdAt: cards.createdAt,
      })
      .from(cardReframes)
      .innerJoin(cards, eq(cards.id, cardReframes.cardId))
      .where(
        and(
          eq(cards.userId, viewerId),
          eq(cardReframes.isFavorite, true),
          lte(cards.createdAt, before),
          or(isNull(cardReframes.favoritedAt), lte(cardReframes.favoritedAt, before)),
        ),
      )
      .orderBy(desc(cardReframes.favoritedAt), desc(cards.id))
      .limit(limit),
  ]);

  return [
    ...saved,
    ...own.map(({ createdAt, at, ...row }) => ({ ...row, at: at ?? createdAt })),
  ];
}

/**
 * What the viewer is mostly in, from what they wrote and from every angle they hearted on
 * any tab. This is the recognition term: the reason their feed should not read like a
 * stranger's. Hearting three angles of one card is one signal about the card's theme.
 * Read as of `now`: a ranked visit passes its start, so nothing after it moves the order.
 */
export async function loadViewerAffinity(
  viewerId: string,
  now: Date,
  db: ReturnType<typeof getDb>,
): Promise<ViewerAffinity> {
  const [authored, hearts] = await Promise.all([
    db
      .select({ category: cards.category, emotions: cards.emotions, at: cards.createdAt })
      .from(cards)
      .where(and(eq(cards.userId, viewerId), lte(cards.createdAt, now)))
      .orderBy(desc(cards.createdAt), desc(cards.id))
      .limit(AFFINITY_SAMPLE),
    loadViewerHearts(viewerId, db, AFFINITY_SAMPLE * 2, now),
  ]);

  const latestHeart = new Map<string, HeartRow>();
  for (const row of hearts) {
    const seen = latestHeart.get(row.cardId);
    if (!seen || row.at > seen.at) {
      latestHeart.set(row.cardId, row);
    }
  }

  return buildAffinity(
    [
      ...authored.map((row) => ({ ...row, source: "authored" as const })),
      ...[...latestHeart.values()].map((row) => ({ ...row, source: "hearted" as const })),
    ],
    now,
  );
}

/**
 * Taste learned from the angles this viewer hearted, for each of the four tabs, in one
 * pass. `hearts` is the sample size, which is enough: confidence saturates at five.
 */
async function loadViewerStyleTabs(
  viewerId: string,
  now: Date,
  db: ReturnType<typeof getDb>,
): Promise<StyleTabs> {
  const hearts = await loadViewerHearts(viewerId, db, AFFINITY_SAMPLE * STYLES.length, now);
  const tab = (style: Style): StyleTabContext => {
    const rows = hearts
      .filter((row) => row.style === style)
      .sort((left, right) => right.at.getTime() - left.at.getTime())
      .slice(0, AFFINITY_SAMPLE);
    return {
      affinity: buildAffinity(
        rows.map((row) => ({ ...row, source: "hearted" as const })),
        now,
      ),
      hearts: rows.length,
    };
  };
  return {
    stoic: tab("stoic"),
    optimistic: tab("optimistic"),
    humorous: tab("humorous"),
    tough_love: tab("tough_love"),
  };
}

/**
 * The angles of these cards the viewer hearted up to `before`: strangers' cards through
 * `saved_angles`, and their own cards through the favorite flag on the angle.
 */
async function loadKeptAngles(
  viewerId: string,
  cardIds: string[],
  before: Date,
  db: ReturnType<typeof getDb>,
): Promise<Map<string, Set<Style>>> {
  const kept = new Map<string, Set<Style>>();
  if (cardIds.length === 0) {
    return kept;
  }
  const [saved, own] = await Promise.all([
    db
      .select({ cardId: savedAngles.cardId, style: savedAngles.style })
      .from(savedAngles)
      .where(
        and(
          eq(savedAngles.userId, viewerId),
          inArray(savedAngles.cardId, cardIds),
          lte(savedAngles.favoritedAt, before),
        ),
      ),
    db
      .select({ cardId: cardReframes.cardId, style: cardReframes.style })
      .from(cardReframes)
      .innerJoin(cards, eq(cards.id, cardReframes.cardId))
      .where(
        and(
          eq(cards.userId, viewerId),
          inArray(cardReframes.cardId, cardIds),
          eq(cardReframes.isFavorite, true),
          or(isNull(cardReframes.favoritedAt), lte(cardReframes.favoritedAt, before)),
        ),
      ),
  ]);
  for (const row of [...saved, ...own]) {
    const styles = kept.get(row.cardId) ?? new Set<Style>();
    styles.add(row.style);
    kept.set(row.cardId, styles);
  }
  return kept;
}

/** The angles each candidate card has, so a card is never assigned a tab it cannot show. */
async function loadCardStyles(
  cardIds: string[],
  db: ReturnType<typeof getDb>,
): Promise<Map<string, Style[]>> {
  const styles = new Map<string, Style[]>();
  if (cardIds.length === 0) {
    return styles;
  }
  const rows = await db
    .select({ cardId: cardReframes.cardId, style: cardReframes.style })
    .from(cardReframes)
    .where(inArray(cardReframes.cardId, cardIds));
  for (const row of rows) {
    const list = styles.get(row.cardId) ?? [];
    list.push(row.style);
    styles.set(row.cardId, list);
  }
  return styles;
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
