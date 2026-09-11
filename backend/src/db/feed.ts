import { and, arrayOverlaps, asc, desc, eq, inArray, lt, ne, or } from "drizzle-orm";
import { getOwnerUserId } from "../lib/authStub.js";
import type { FeedListQuery, StoredCard, Style } from "../types/index.js";
import { DbError, getDb, wrapDbError } from "./client.js";
import { loadViewerSaves, toStoredCard, type CardLoaded } from "./mapCard.js";
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

export async function listFeed(query: FeedListQuery): Promise<StoredCard[]> {
  try {
    const viewerId = getOwnerUserId();
    const db = getDb();
    const filters = [eq(cards.isPublic, true), ne(cards.userId, viewerId)];
    if (query.categories?.length) {
      filters.push(inArray(cards.category, query.categories));
    }
    if (query.emotions?.length) {
      filters.push(arrayOverlaps(cards.emotions, query.emotions));
    }
    if (query.before) {
      const cursorFilter = or(
        lt(cards.createdAt, query.before.createdAt),
        and(eq(cards.createdAt, query.before.createdAt), lt(cards.id, query.before.id)),
      );
      if (cursorFilter) {
        filters.push(cursorFilter);
      }
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

    const saves = await loadViewerSaves(viewerId);
    return rows.map((row) => toStoredCard(row, saves, viewerId));
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "listFeed");
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
  const saves = await loadViewerSaves(viewerId, db);
  return { ok: true, card: toStoredCard(row, saves, viewerId) };
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

export async function clearFeedSaves(id: string): Promise<FeedSaveResult> {
  return withFeedTarget(id, async (tx, _row, viewerId) => {
    await tx.delete(savedAngles).where(and(eq(savedAngles.userId, viewerId), eq(savedAngles.cardId, id)));
    return returnViewerCard(tx, id, viewerId);
  });
}
