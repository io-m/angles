import {
  and,
  arrayOverlaps,
  asc,
  desc,
  eq,
  inArray,
  isNull,
  lte,
  ne,
  notInArray,
  or,
  sql,
  type SQL,
} from "drizzle-orm";
import { getOwnerUserId } from "../lib/authStub.js";
import { isSolemnSkip } from "../lib/decision.js";
import {
  buildAffinity,
  classifyTheme,
  followMix,
  HEAVY_INTENSITY,
  rankCards,
  RETURN_AFTER_HOURS,
  spreadRanked,
  themeMix,
  type ViewerAffinity,
} from "../lib/feedRanking.js";
import { isStyleShown } from "../lib/styleSet.js";
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
import { storedCardsForViewer } from "./mapCard.js";
import { loadCardSaveTotals, loadViewerSavedStyle } from "./saves.js";
import { cardDecisions, cardReframes, cards, users } from "./schema.js";

type Db = ReturnType<typeof getDb>;

/** Cards scored per visit. Bounded so one request cannot rank the whole catalog. */
const STACK_CANDIDATE_CAP = 1000;

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

/**
 * One page of a visit's stack: someone else's public cards the viewer has not decided,
 * plus passed cards that may come back once. Community cards first, then the house cards.
 *
 * Every ranking input (saves, follows, themes, the clock, what counts as returning) is read
 * as of `session.startedAt`, so the cards left keep their order however many are decided
 * while the visit lasts. Paging is by exclusion, not offset: a card decided since is gone
 * from the database's point of view, and `seen` drops the ones still waiting on the phone.
 */
export async function listStack(query: StackQuery, ranked: boolean): Promise<StackPage> {
  try {
    const viewerId = getOwnerUserId();
    const db = getDb();
    const { startedAt, seed } = query.session;
    const candidates = await loadCandidates(viewerId, query, db);
    if (candidates.length === 0) {
      return { cards: [], exhausted: true };
    }

    const community = candidates.filter((card) => !card.isHouse);
    const house = candidates.filter((card) => card.isHouse);
    let order: Candidate[];
    if (ranked) {
      const afterHeavy = await lastSeenWasHeavy(query.seen, db);
      const [saves, followed, affinity] = await Promise.all([
        loadCardSaveTotals(
          candidates.map((card) => card.id),
          db,
          { before: startedAt, excludeUserId: viewerId },
        ),
        followedAuthorIds(
          viewerId,
          community.map((card) => card.authorId),
          db,
          startedAt,
        ),
        loadViewerAffinity(viewerId, startedAt, db),
      ]);
      const rankGroup = (group: Candidate[], previousHeavy: boolean): Candidate[] => {
        const byId = new Map(
          group.map((card) => [
            card.id,
            {
              ...card,
              bucket: classifyTheme(card, affinity),
              followed: followed.has(card.authorId),
            },
          ]),
        );
        const scored = rankCards(
          group.map((card) => ({
            id: card.id,
            authorId: card.authorId,
            createdAt: card.createdAt,
            category: card.category,
            emotions: card.emotions,
            saves: saves.get(card.id) ?? 0,
            followed: followed.has(card.authorId),
            returning: card.returning,
          })),
          { now: startedAt, seed, affinity },
        );
        const spreadable = scored.flatMap((item) => {
          const card = byId.get(item.id);
          return card ? [card] : [];
        });
        return spreadRanked(spreadable, query.limit, {
          mix: themeMix(affinity.confidence),
          follow: followMix(spreadable, startedAt),
          afterHeavy: previousHeavy,
        });
      };
      const rankedCommunity = rankGroup(community, afterHeavy);
      const lastCommunity = rankedCommunity[rankedCommunity.length - 1];
      order = [
        ...rankedCommunity,
        ...rankGroup(house, lastCommunity ? lastCommunity.heavy : afterHeavy),
      ];
    } else {
      // Unranked: newest first, the house cards still last.
      order = [...community, ...house];
    }

    const pageIds = order.slice(0, query.limit).map((card) => card.id);
    if (pageIds.length === 0) {
      return { cards: [], exhausted: true };
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
    const [followed, preferredStyle] = await Promise.all([
      followedAuthorIds(
        viewerId,
        ordered.map((row) => row.userId),
        db,
        startedAt,
      ),
      loadViewerSavedStyle(viewerId, db, startedAt),
    ]);
    return {
      cards: await storedCardsForViewer(ordered, viewerId, db, { followed, preferredStyle }),
      exhausted: order.length <= query.limit,
    };
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "listStack");
  }
}

/**
 * Public, someone else's, visible to this viewer, posted by the visit's start, not handed
 * out yet this visit, and either never decided or passed once at least
 * `RETURN_AFTER_HOURS` before the visit with an angle the viewer has not seen.
 */
async function loadCandidates(viewerId: string, query: StackQuery, db: Db): Promise<Candidate[]> {
  const { startedAt } = query.session;
  const { seen } = query;
  const returnBy = new Date(startedAt.getTime() - RETURN_AFTER_HOURS * 3_600_000);
  // A literal, not a bound parameter, so even a generic plan can prove the partial index applies.
  const filters: SQL[] = [
    sql`${cards.isPublic} = true`,
    ne(cards.userId, viewerId),
    notBlockedBetween(viewerId, cards.userId),
    notReportedBy(viewerId, cards.id),
    sql`${cards.createdAt} <= ${startedAt.toISOString()}::timestamptz`,
    or(
      isNull(cardDecisions.cardId),
      and(
        eq(cardDecisions.kind, "pass"),
        sql`${cardDecisions.passes} < ${MAX_PASSES}`,
        lte(cardDecisions.decidedAt, returnBy),
      ),
    )!,
  ];
  if (seen.length > 0) {
    filters.push(notInArray(cards.id, [...seen]));
  }
  if (query.categories?.length) {
    filters.push(inArray(cards.category, query.categories));
  }
  if (query.emotions?.length) {
    filters.push(arrayOverlaps(cards.emotions, query.emotions));
  }

  const found = await db
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
    })
    .from(cards)
    .innerJoin(users, eq(users.id, cards.userId))
    .leftJoin(
      cardDecisions,
      and(eq(cardDecisions.cardId, cards.id), eq(cardDecisions.userId, viewerId)),
    )
    .where(and(...filters))
    .orderBy(desc(cards.createdAt), desc(cards.id))
    .limit(STACK_CANDIDATE_CAP);

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
    const returning = checked !== null;
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

/** Whether the card the phone got last was heavy, so a new page does not open on another. */
async function lastSeenWasHeavy(seen: readonly string[], db: Db): Promise<boolean> {
  const last = seen[seen.length - 1];
  if (!last) {
    return false;
  }
  const [row] = await db
    .select({
      category: cards.category,
      intensity: cards.intensity,
      skippedStyles: cards.skippedStyles,
    })
    .from(cards)
    .where(eq(cards.id, last))
    .limit(1);
  return row ? isHeavyCard(row) : false;
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
      .select({ category: cards.category, emotions: cards.emotions, at: cards.createdAt })
      .from(cards)
      .where(and(eq(cards.userId, viewerId), lte(cards.createdAt, now)))
      .orderBy(desc(cards.createdAt), desc(cards.id))
      .limit(AFFINITY_SAMPLE),
    db
      .select({
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

  return buildAffinity(
    [
      ...authored.map((row) => ({ ...row, source: "authored" as const })),
      ...decided.map((row) => ({
        category: row.category,
        emotions: row.emotions,
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
