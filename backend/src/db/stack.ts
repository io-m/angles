import {
  and,
  arrayOverlaps,
  asc,
  desc,
  eq,
  gt,
  inArray,
  isNotNull,
  isNull,
  lte,
  ne,
  or,
  sql,
  type SQL,
} from "drizzle-orm";
import { getOwnerUserId } from "../lib/authStub.js";
import { isSolemnSkip } from "../lib/decision.js";
import {
  buildAffinity,
  classifyTheme,
  emptyVisitSpread,
  EXPLORATION,
  followMix,
  HEAVY_INTENSITY,
  qualityBaselines,
  rankCards,
  RETURN_AFTER_HOURS,
  spreadRanked,
  themeMix,
  type ThemeBucket,
  type ViewerAffinity,
  type VisitSpread,
} from "../lib/feedRanking.js";
import { isStyleShown, stylesForRequest } from "../lib/styleSet.js";
import {
  MAX_PASSES,
  type Category,
  type FeedCursor,
  type SkippedStyle,
  type StackQuery,
  type StoredCard,
  type Style,
} from "../types/index.js";
import { DbError, getDb, wrapDbError } from "./client.js";
import { notBlockedBetween, notReportedBy } from "./communitySafety.js";
import { olderThanCursor } from "./cursor.js";
import { followedAuthorIds } from "./follows.js";
import { storedCardsForViewer, type CardLoaded } from "./mapCard.js";
import { loadCardDecisionTotals, loadViewerSavedStyle } from "./saves.js";
import { cardDecisions, cardReframes, cardTags, cards, follows, tags, users } from "./schema.js";

type Db = ReturnType<typeof getDb>;

/**
 * How many candidates each slice of the catalog contributes to a visit. Picking only the
 * newest would starve every older card past that count, however well people kept it, so
 * the pool is the newest cards plus the ones that have a reason to be there anyway.
 */
const CANDIDATE_STRATA = {
  newest: 600,
  followed: 150,
  returning: 100,
  /** Cards too few people have decided on yet, newest first. */
  exploring: 150,
  /** Older cards the most people kept. */
  kept: 150,
  house: 200,
} as const;

/** Extra ids read per page load, so a card that went private since does not leave it short. */
const PAGE_SLACK = 4;

/** A card that should never sit right after another like it: real harm, or a hard day. */
export function isHeavyCard(card: {
  category: Category;
  intensity: number;
  skippedStyles: readonly SkippedStyle[];
}): boolean {
  return (
    card.category === "grief_loss" ||
    card.intensity >= HEAVY_INTENSITY ||
    card.skippedStyles.some(isSolemnSkip)
  );
}

type Candidate = {
  id: string;
  authorId: string;
  isHouse: boolean;
  createdAt: Date;
  category: Category;
  emotions: StoredCard["emotions"];
  intensity: number;
  spotlightStyle: Style;
  heavy: boolean;
  returning: boolean;
};

export type StackPage = { cards: StoredCard[]; exhausted: boolean };

/** A visit's whole order and what every page of it reads the same way. */
type VisitOrder = {
  order: string[];
  followed: ReadonlySet<string>;
  preferredStyle: Style | null;
};

const VISIT_CACHE_LIMIT = 300;
/** Longer than a visit lasts: 30 minutes away starts a new one. */
const VISIT_CACHE_TTL_MS = 45 * 60_000;
const visitCache = new Map<string, VisitOrder & { expiresAt: number }>();

function visitCacheEnabled(): boolean {
  return process.env.STACK_CACHE?.trim().toLowerCase() !== "off";
}

/** For tests that change the catalog under one session. */
export function clearStackCache(): void {
  visitCache.clear();
}

function visitKey(viewerId: string, query: StackQuery, ranked: boolean): string {
  return [
    viewerId,
    query.session.seed,
    query.session.startedAt.toISOString(),
    query.limit,
    query.categories?.join(",") ?? "",
    query.emotions?.join(",") ?? "",
    stylesForRequest().join(","),
    ranked ? "ranked" : "newest",
  ].join("|");
}

function cachedVisit(key: string, now: number): VisitOrder | null {
  const hit = visitCache.get(key);
  if (!hit) {
    return null;
  }
  visitCache.delete(key);
  if (hit.expiresAt <= now) {
    return null;
  }
  // Re-inserted, so the Map's insertion order is least recently used first.
  visitCache.set(key, hit);
  return hit;
}

function rememberVisit(key: string, visit: VisitOrder, now: number): void {
  visitCache.set(key, { ...visit, expiresAt: now + VISIT_CACHE_TTL_MS });
  while (visitCache.size > VISIT_CACHE_LIMIT) {
    const oldest = visitCache.keys().next().value;
    if (oldest === undefined) {
      break;
    }
    visitCache.delete(oldest);
  }
}

/**
 * One page of a visit's stack: someone else's public cards the viewer has not decided,
 * plus passed cards that may come back once. Community cards first, then the house cards.
 *
 * The visit's whole order is ranked and spread once, from inputs read as of
 * `session.startedAt`, and kept in memory; a page only drops what this visit already
 * handed out or decided and loads the next cards. On a cache miss (a restart, another
 * replica) the same inputs give the same order. A card that went private, was reported,
 * or whose author was blocked since is skipped when its page loads.
 */
export async function listStack(query: StackQuery, ranked: boolean): Promise<StackPage> {
  try {
    const viewerId = getOwnerUserId();
    const db = getDb();
    const visit = await visitOrder(viewerId, query, ranked, db);
    if (visit.order.length === 0) {
      return { cards: [], exhausted: true };
    }
    const excluded = new Set(query.seen);
    for (const id of await decidedSince(viewerId, query.session.startedAt, db)) {
      excluded.add(id);
    }
    const remaining = visit.order.filter((id) => !excluded.has(id));
    const { rows, lastIndex } = await loadPage(remaining, query.limit, viewerId, db);
    return {
      cards: await storedCardsForViewer(rows, viewerId, db, {
        followed: visit.followed,
        preferredStyle: visit.preferredStyle,
      }),
      exhausted: lastIndex >= remaining.length - 1,
    };
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "listStack");
  }
}

async function visitOrder(
  viewerId: string,
  query: StackQuery,
  ranked: boolean,
  db: Db,
): Promise<VisitOrder> {
  if (!visitCacheEnabled()) {
    return buildVisit(viewerId, query, ranked, db);
  }
  const key = visitKey(viewerId, query, ranked);
  const now = Date.now();
  const hit = cachedVisit(key, now);
  if (hit) {
    return hit;
  }
  const visit = await buildVisit(viewerId, query, ranked, db);
  rememberVisit(key, visit, now);
  return visit;
}

/** Cards this viewer decided on (or rewound back to a row) since the visit began. */
async function decidedSince(viewerId: string, startedAt: Date, db: Db): Promise<string[]> {
  const rows = await db
    .select({ id: cardDecisions.cardId })
    .from(cardDecisions)
    .where(and(eq(cardDecisions.userId, viewerId), gt(cardDecisions.decidedAt, startedAt)));
  return rows.map((row) => row.id);
}

/**
 * The next `limit` cards of `ids` that are still public and visible to the viewer, in
 * order. `lastIndex` is the last id examined, so the caller knows whether any are left.
 */
async function loadPage(
  ids: readonly string[],
  limit: number,
  viewerId: string,
  db: Db,
): Promise<{ rows: CardLoaded[]; lastIndex: number }> {
  const rows: CardLoaded[] = [];
  let cursor = 0;
  let lastIndex = -1;
  while (rows.length < limit && cursor < ids.length) {
    const chunk = ids.slice(cursor, cursor + limit - rows.length + PAGE_SLACK);
    const found = await db.query.cards.findMany({
      where: and(
        inArray(cards.id, [...chunk]),
        sql`${cards.isPublic} = true`,
        ne(cards.userId, viewerId),
        notBlockedBetween(viewerId, cards.userId),
        notReportedBy(viewerId, cards.id),
      ),
      with: {
        user: true,
        reframes: { orderBy: [asc(cardReframes.position)] },
        cardTags: { with: { tag: true } },
      },
    });
    const byId = new Map(found.map((row) => [row.id, row]));
    for (const [offset, id] of chunk.entries()) {
      if (rows.length >= limit) {
        break;
      }
      lastIndex = cursor + offset;
      const row = byId.get(id);
      if (row) {
        rows.push(row);
      }
    }
    cursor += chunk.length;
  }
  return { rows, lastIndex };
}

type RankedCandidate = Candidate & {
  saves: number;
  decisions: number;
  tags: string[];
  followed: boolean;
  bucket: ThemeBucket;
  exploring: boolean;
};

async function buildVisit(
  viewerId: string,
  query: StackQuery,
  ranked: boolean,
  db: Db,
): Promise<VisitOrder> {
  const { startedAt, seed } = query.session;
  const candidates = await loadCandidates(viewerId, query, db);
  const community = candidates.filter((card) => !card.isHouse);
  const house = candidates.filter((card) => card.isHouse);
  const [followed, preferredStyle] = await Promise.all([
    followedAuthorIds(
      viewerId,
      community.map((card) => card.authorId),
      db,
      startedAt,
    ),
    loadViewerSavedStyle(viewerId, db, startedAt),
  ]);
  if (!ranked || candidates.length === 0) {
    // Unranked: newest first, the house cards still last.
    return { order: [...community, ...house].map((card) => card.id), followed, preferredStyle };
  }

  const ids = candidates.map((card) => card.id);
  const [totals, tagsById, affinity] = await Promise.all([
    loadCardDecisionTotals(ids, db, { before: startedAt, excludeUserId: viewerId }),
    loadCardTagSlugs(ids, db),
    loadViewerAffinity(viewerId, startedAt, db),
  ]);
  const enrich = (card: Candidate): RankedCandidate => {
    const total = totals.get(card.id) ?? { saves: 0, decisions: 0 };
    return {
      ...card,
      saves: total.saves,
      decisions: total.decisions,
      tags: tagsById.get(card.id) ?? [],
      followed: !card.isHouse && followed.has(card.authorId),
      bucket: classifyTheme(card, affinity),
      exploring: !card.returning && total.decisions < EXPLORATION.maxDecisions,
    };
  };
  const rankedCommunity = community.map(enrich);
  const rankedHouse = house.map(enrich);
  const baselines = qualityBaselines(rankedCommunity);
  const mix = themeMix(affinity.confidence);

  const rankGroup = (group: RankedCandidate[], visit: VisitSpread): RankedCandidate[] => {
    const byId = new Map(group.map((card) => [card.id, card]));
    const scored = rankCards(group, { now: startedAt, seed, affinity, baselines });
    const spreadable = scored.flatMap((item) => {
      const card = byId.get(item.id);
      return card ? [card] : [];
    });
    return spreadRanked(spreadable, query.limit, {
      mix,
      follow: followMix(spreadable, startedAt),
      exploreShare: EXPLORATION.share,
      visit,
    });
  };
  const communityOrder = rankGroup(rankedCommunity, emptyVisitSpread());
  const lastCommunity = communityOrder[communityOrder.length - 1];
  // House cards are one author, so they get their own spread; only pacing carries over.
  const houseOrder = rankGroup(rankedHouse, emptyVisitSpread(lastCommunity?.heavy ?? false));
  return {
    order: [...communityOrder, ...houseOrder].map((card) => card.id),
    followed,
    preferredStyle,
  };
}

type CandidateRow = {
  id: string;
  authorId: string;
  authorKind: "person" | "house";
  createdAt: Date;
  category: Category;
  emotions: StoredCard["emotions"];
  intensity: number;
  spotlightStyle: Style;
  skippedStyles: SkippedStyle[];
  checkedStyles: Style[] | null;
  decidedAt: Date | null;
};

/**
 * Public, someone else's, visible to this viewer, posted by the visit's start, and either
 * never decided, passed once at least `RETURN_AFTER_HOURS` before the visit with an angle
 * the viewer has not seen, or decided only since the visit began. That last group is
 * dropped again page by page; keeping it here means a rebuilt order matches the first.
 *
 * Drawn from several slices of the catalog (`CANDIDATE_STRATA`), deduplicated.
 */
async function loadCandidates(viewerId: string, query: StackQuery, db: Db): Promise<Candidate[]> {
  const { startedAt } = query.session;
  const startedAtSql = sql`${startedAt.toISOString()}::timestamptz`;
  const returnBy = new Date(startedAt.getTime() - RETURN_AFTER_HOURS * 3_600_000);
  // A literal, not a bound parameter, so even a generic plan can prove the partial index applies.
  const base: SQL[] = [
    sql`${cards.isPublic} = true`,
    ne(cards.userId, viewerId),
    notBlockedBetween(viewerId, cards.userId),
    notReportedBy(viewerId, cards.id),
    sql`${cards.createdAt} <= ${startedAtSql}`,
    or(
      isNull(cardDecisions.cardId),
      and(
        eq(cardDecisions.kind, "pass"),
        sql`${cardDecisions.passes} < ${MAX_PASSES}`,
        lte(cardDecisions.decidedAt, returnBy),
      ),
      gt(cardDecisions.decidedAt, startedAt),
    )!,
  ];
  if (query.categories?.length) {
    base.push(inArray(cards.category, query.categories));
  }
  if (query.emotions?.length) {
    base.push(arrayOverlaps(cards.emotions, query.emotions));
  }

  const othersDecided = sql`(
    select count(*) from "card_decisions" as "others"
    where "others"."card_id" = ${cards.id}
      and "others"."user_id" <> ${viewerId}
      and "others"."decided_at" <= ${startedAtSql}
  )`;
  const othersSaved = sql`(
    select count(*) from "card_decisions" as "others"
    where "others"."card_id" = ${cards.id}
      and "others"."user_id" <> ${viewerId}
      and "others"."kind" = 'save'
      and "others"."decided_at" <= ${startedAtSql}
  )`;
  const person = eq(users.kind, "person");
  const newestFirst = [desc(cards.createdAt), desc(cards.id)];

  const slice = (extra: SQL[], order: SQL[], limit: number): Promise<CandidateRow[]> =>
    db
      .select({
        id: cards.id,
        authorId: cards.userId,
        authorKind: users.kind,
        createdAt: cards.createdAt,
        category: cards.category,
        emotions: cards.emotions,
        intensity: cards.intensity,
        spotlightStyle: cards.spotlightStyle,
        skippedStyles: cards.skippedStyles,
        checkedStyles: cardDecisions.checkedStyles,
        decidedAt: cardDecisions.decidedAt,
      })
      .from(cards)
      .innerJoin(users, eq(users.id, cards.userId))
      .leftJoin(
        cardDecisions,
        and(eq(cardDecisions.cardId, cards.id), eq(cardDecisions.userId, viewerId)),
      )
      .where(and(...base, ...extra))
      .orderBy(...order)
      .limit(limit);

  const followees = db
    .select({ id: follows.followeeId })
    .from(follows)
    .where(and(eq(follows.followerId, viewerId), lte(follows.createdAt, startedAt)));

  const slices = await Promise.all([
    slice([person], newestFirst, CANDIDATE_STRATA.newest),
    slice([person, inArray(cards.userId, followees)], newestFirst, CANDIDATE_STRATA.followed),
    slice([person, isNotNull(cardDecisions.cardId)], newestFirst, CANDIDATE_STRATA.returning),
    slice(
      [person, sql`${othersDecided} < ${EXPLORATION.maxDecisions}`],
      newestFirst,
      CANDIDATE_STRATA.exploring,
    ),
    slice([person, sql`${othersSaved} > 0`], [sql`${othersSaved} desc`, ...newestFirst], CANDIDATE_STRATA.kept),
    slice([eq(users.kind, "house")], newestFirst, CANDIDATE_STRATA.house),
  ]);

  const unique = new Map<string, CandidateRow>();
  for (const row of slices.flat()) {
    if (!unique.has(row.id)) {
      unique.set(row.id, row);
    }
  }
  const found = [...unique.values()].sort(
    (left, right) =>
      right.createdAt.getTime() - left.createdAt.getTime() || (left.id < right.id ? 1 : -1),
  );

  const styles = await loadCardStyles(
    found.map((row) => row.id),
    db,
  );
  return found.flatMap((row): Candidate[] => {
    const available = styles.get(row.id) ?? [];
    // An app that cannot show any of a card's angles never gets it.
    if (available.length === 0) {
      return [];
    }
    const checked = row.checkedStyles;
    // A row written during this visit says nothing about whether the card was returning.
    const decidedBefore = row.decidedAt !== null && row.decidedAt <= startedAt;
    const returning = checked !== null && decidedBefore;
    if (returning && available.every((style) => checked.includes(style))) {
      return [];
    }
    return [
      {
        id: row.id,
        authorId: row.authorId,
        isHouse: row.authorKind === "house",
        createdAt: row.createdAt,
        category: row.category,
        emotions: row.emotions,
        intensity: row.intensity,
        spotlightStyle: row.spotlightStyle,
        heavy: isHeavyCard(row),
        returning,
      },
    ];
  });
}

/** The angles each card has that the calling app can show, in the cook's order. */
async function loadCardStyles(cardIds: string[], db: Db): Promise<Map<string, Style[]>> {
  const styles = new Map<string, Style[]>();
  if (cardIds.length === 0) {
    return styles;
  }
  const rows = await db
    .select({ cardId: cardReframes.cardId, style: cardReframes.style })
    .from(cardReframes)
    .where(inArray(cardReframes.cardId, cardIds))
    .orderBy(asc(cardReframes.cardId), asc(cardReframes.position));
  for (const row of rows) {
    if (!isStyleShown(row.style)) {
      continue;
    }
    const list = styles.get(row.cardId) ?? [];
    list.push(row.style);
    styles.set(row.cardId, list);
  }
  return styles;
}

/** Tag slugs per card. */
async function loadCardTagSlugs(cardIds: string[], db: Db): Promise<Map<string, string[]>> {
  const byCard = new Map<string, string[]>();
  if (cardIds.length === 0) {
    return byCard;
  }
  const rows = await db
    .select({ cardId: cardTags.cardId, slug: tags.slug })
    .from(cardTags)
    .innerJoin(tags, eq(tags.id, cardTags.tagId))
    .where(inArray(cardTags.cardId, cardIds));
  for (const row of rows) {
    const list = byCard.get(row.cardId) ?? [];
    list.push(row.slug);
    byCard.set(row.cardId, list);
  }
  return byCard;
}

/** Recent activity read per source when learning themes. */
const AFFINITY_SAMPLE = 30;

/**
 * What the viewer is mostly in: what they wrote, what they saved, and a little against
 * what they passed. Read as of `now`; a visit passes its start, so a save made during
 * it shapes the next visit, not the cards left in this one.
 */
export async function loadViewerAffinity(
  viewerId: string,
  now: Date,
  db: Db = getDb(),
): Promise<ViewerAffinity> {
  const [authored, decided] = await Promise.all([
    db
      .select({
        id: cards.id,
        category: cards.category,
        emotions: cards.emotions,
        at: cards.createdAt,
      })
      .from(cards)
      .where(and(eq(cards.userId, viewerId), lte(cards.createdAt, now)))
      .orderBy(desc(cards.createdAt), desc(cards.id))
      .limit(AFFINITY_SAMPLE),
    db
      .select({
        id: cards.id,
        kind: cardDecisions.kind,
        category: cards.category,
        emotions: cards.emotions,
        at: cardDecisions.decidedAt,
      })
      .from(cardDecisions)
      .innerJoin(cards, eq(cards.id, cardDecisions.cardId))
      .where(and(eq(cardDecisions.userId, viewerId), lte(cardDecisions.decidedAt, now)))
      .orderBy(desc(cardDecisions.decidedAt), desc(cards.id))
      .limit(AFFINITY_SAMPLE * 2),
  ]);
  const tagsById = await loadCardTagSlugs(
    [...new Set([...authored, ...decided].map((row) => row.id))],
    db,
  );

  return buildAffinity(
    [
      ...authored.map((row) => ({
        category: row.category,
        emotions: row.emotions,
        tags: tagsById.get(row.id) ?? [],
        at: row.at,
        source: "authored" as const,
      })),
      ...decided.map((row) => ({
        category: row.category,
        emotions: row.emotions,
        tags: tagsById.get(row.id) ?? [],
        at: row.at,
        source: row.kind === "save" ? ("saved" as const) : ("passed" as const),
      })),
    ],
    now,
  );
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
