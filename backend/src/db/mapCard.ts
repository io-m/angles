import { and, eq, inArray } from "drizzle-orm";
import { getOwnerUserId } from "../lib/authStub.js";
import { avatarUrlFor } from "../lib/avatarUrl.js";
import { intensityBand, type StoredCard, type StoredReframeResult, type Style } from "../types/index.js";
import { getDb } from "./client.js";
import { followedAuthorIds } from "./follows.js";
import { savedAngles, type CardReframeRow, type CardRow, type TagRow } from "./schema.js";

type Selectable = Pick<ReturnType<typeof getDb>, "select">;

export type CardLoaded = CardRow & {
  reframes: CardReframeRow[];
  cardTags: { tag: TagRow }[];
  user: { initials: string; avatarKey: string | null };
};

/** A viewer's saves on other people's cards. Hearts are the only save there is. */
export type ViewerSaves = {
  angles: Map<string, Map<Style, Date>>;
};

/** Only the saves on `cardIds`, so the cost follows the page rather than every heart ever made. */
export async function loadViewerSaves(
  cardIds: string[],
  viewerId: string = getOwnerUserId(),
  db: Selectable = getDb(),
): Promise<ViewerSaves> {
  const angles = new Map<string, Map<Style, Date>>();
  if (cardIds.length === 0) {
    return { angles };
  }
  const angleRows = await db
    .select()
    .from(savedAngles)
    .where(and(eq(savedAngles.userId, viewerId), inArray(savedAngles.cardId, cardIds)));

  for (const row of angleRows) {
    let byStyle = angles.get(row.cardId);
    if (!byStyle) {
      byStyle = new Map();
      angles.set(row.cardId, byStyle);
    }
    byStyle.set(row.style, row.favoritedAt);
  }

  return { angles };
}

export function authorOf(
  userId: string,
  user: { initials: string; avatarKey: string | null },
  following: boolean,
): StoredCard["author"] {
  const author: StoredCard["author"] = { id: userId, initials: user.initials, following };
  const avatarUrl = avatarUrlFor(userId, user.avatarKey);
  if (avatarUrl) {
    author.avatarUrl = avatarUrl;
  }
  return author;
}

export async function storedCardsForViewer(
  rows: CardLoaded[],
  viewerId: string = getOwnerUserId(),
  db: Selectable = getDb(),
): Promise<StoredCard[]> {
  const saves = await loadViewerSaves(
    rows.map((row) => row.id),
    viewerId,
    db,
  );
  const followed = await followedAuthorIds(
    viewerId,
    rows.map((row) => row.userId),
    db,
  );
  return rows.map((row) => toStoredCard(row, saves, viewerId, followed));
}

export function toStoredCard(
  row: CardLoaded,
  saves: ViewerSaves,
  viewerId: string = getOwnerUserId(),
  followedIds: ReadonlySet<string> = new Set(),
): StoredCard {
  const isOwner = row.userId === viewerId;
  const savedStyles = saves.angles.get(row.id);
  const tagList = row.cardTags.map((join) => ({
    slug: join.tag.slug,
    label: join.tag.label,
  }));
  const results: StoredReframeResult[] = [...row.reframes]
    .sort((left, right) => left.position - right.position)
    .map((item) => {
      if (isOwner) {
        const stored: StoredReframeResult = {
          style: item.style,
          reframe: item.reframe,
          isFavorite: item.isFavorite,
        };
        if (item.favoritedAt) {
          stored.favoritedAt = item.favoritedAt.toISOString();
        }
        return stored;
      }

      const favoritedAt = savedStyles?.get(item.style);
      const stored: StoredReframeResult = {
        style: item.style,
        reframe: item.reframe,
        isFavorite: favoritedAt !== undefined,
      };
      if (favoritedAt) {
        stored.favoritedAt = favoritedAt.toISOString();
      }
      return stored;
    });

  const stored: StoredCard = {
    id: row.id,
    thought: row.thoughtEn,
    inputLanguage: row.inputLanguage,
    category: row.category,
    tags: tagList,
    intensity: row.intensity,
    intensityBand: intensityBand(row.intensity),
    timeframe: row.timeframe,
    emotions: row.emotions,
    safety: row.safety,
    skippedStyles: row.skippedStyles,
    matching: {
      category: row.category,
      tags: tagList.map((tag) => tag.slug),
      intensityBand: intensityBand(row.intensity),
    },
    results,
    model: row.model,
    spotlightStyle: row.spotlightStyle,
    isPublic: row.isPublic,
    createdAt: row.createdAt.toISOString(),
    isOwner,
    author: authorOf(row.userId, row.user, !isOwner && followedIds.has(row.userId)),
  };

  if (row.thoughtOriginal) {
    stored.thoughtOriginal = row.thoughtOriginal;
  }
  if (row.proposedCategory) {
    stored.proposedCategory = row.proposedCategory;
  }
  if (row.proposedLabel) {
    stored.proposedLabel = row.proposedLabel;
  }

  return stored;
}
