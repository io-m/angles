import { and, arrayOverlaps, asc, desc, eq, inArray, sql } from "drizzle-orm";
import { getOwnerUserId } from "../lib/authStub.js";
import type { FeedCursor, FeedListQuery, StoredCard, Style } from "../types/index.js";
import { DbError, getDb, wrapDbError } from "./client.js";
import { olderThanCursor } from "./cursor.js";
import { storedCardsForViewer, type CardLoaded } from "./mapCard.js";
import { cardReframes, cards, savedAngles } from "./schema.js";

type Queryable = { query: ReturnType<typeof getDb>["query"] };

async function loadFeedCardRow(db: Queryable, id: string): Promise<CardLoaded | null> {
  const row = await db.query.cards.findFirst({
    where: eq(cards.id, id),
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

export async function listFeed(query: FeedListQuery): Promise<StoredCard[]> {
  try {
    const viewerId = getOwnerUserId();
    const db = getDb();
    // A literal, not a bound parameter, so even a generic plan can prove the partial index applies.
    const filters = [sql`${cards.isPublic} = true`];
    if (query.categories?.length) {
      filters.push(inArray(cards.category, query.categories));
    }
    if (query.emotions?.length) {
      filters.push(arrayOverlaps(cards.emotions, query.emotions));
    }
    if (query.style) {
      filters.push(styleExistsFilter(db, query.style));
    }
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
    throw wrapDbError(error, "listFeed");
  }
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
    const filters = [eq(cards.userId, query.userId), eq(cards.isPublic, true)];
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
    const filters = [eq(cards.model, query.model), sql`${cards.isPublic} = true`];
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
      const row = await loadFeedCardRow(tx, id);
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
  const row = await loadFeedCardRow(db, id);
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
    const removed = await getDb()
      .delete(savedAngles)
      .where(and(eq(savedAngles.userId, viewerId), eq(savedAngles.cardId, id)))
      .returning({ cardId: savedAngles.cardId });
    if (removed.length > 0) {
      return { ok: true };
    }
    const row = await loadFeedCardRow(getDb(), id);
    return { ok: row !== null && isFeedSaveTarget(row, viewerId) };
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "clearFeedSaves");
  }
}
