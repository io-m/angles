import { and, arrayContains, asc, desc, eq, inArray, lt, ne } from "drizzle-orm";
import { getOwnerUserId } from "../lib/authStub.js";
import { groupHomeFeed } from "../lib/homeFeed.js";
import type { FeedHomeQuery, FeedHomeResponse, FeedListQuery, StoredCard, Style } from "../types/index.js";
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
    if (query.category) {
      filters.push(eq(cards.category, query.category));
    }
    if (query.style) {
      filters.push(
        inArray(
          cards.id,
          db.select({ id: cardReframes.cardId }).from(cardReframes).where(eq(cardReframes.style, query.style)),
        ),
      );
    }
    if (query.emotion) {
      filters.push(arrayContains(cards.emotions, [query.emotion]));
    }
    if (query.before) {
      filters.push(lt(cards.createdAt, query.before));
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

/** One scan is enough to fill every capped shelf; the payload the app gets is the grouped subset. */
const HOME_SCAN_LIMIT = 500;

export async function listHomeFeed(query: FeedHomeQuery): Promise<FeedHomeResponse> {
  const cardList = await listFeed({ limit: HOME_SCAN_LIMIT, style: query.style });
  return groupHomeFeed(cardList, query.perSection);
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
