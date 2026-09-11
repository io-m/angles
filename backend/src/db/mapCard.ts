import { eq } from "drizzle-orm";
import { getOwnerUserId } from "../lib/authStub.js";
import { intensityBand, type StoredCard, type StoredReframeResult, type Style } from "../types/index.js";
import { getDb } from "./client.js";
import { savedAngles, savedPins, type CardReframeRow, type CardRow, type TagRow } from "./schema.js";

type Selectable = Pick<ReturnType<typeof getDb>, "select">;

export type CardLoaded = CardRow & {
  reframes: CardReframeRow[];
  cardTags: { tag: TagRow }[];
  user: { initials: string };
};

export type ViewerSaves = {
  pins: Map<string, Date>;
  angles: Map<string, Map<Style, Date>>;
};

export async function loadViewerSaves(
  viewerId: string = getOwnerUserId(),
  db: Selectable = getDb(),
): Promise<ViewerSaves> {
  const [pinRows, angleRows] = await Promise.all([
    db.select().from(savedPins).where(eq(savedPins.userId, viewerId)),
    db.select().from(savedAngles).where(eq(savedAngles.userId, viewerId)),
  ]);

  const pins = new Map<string, Date>();
  for (const row of pinRows) {
    pins.set(row.cardId, row.pinnedAt);
  }

  const angles = new Map<string, Map<Style, Date>>();
  for (const row of angleRows) {
    let byStyle = angles.get(row.cardId);
    if (!byStyle) {
      byStyle = new Map();
      angles.set(row.cardId, byStyle);
    }
    byStyle.set(row.style, row.favoritedAt);
  }

  return { pins, angles };
}

export function toStoredCard(row: CardLoaded, saves: ViewerSaves, viewerId: string = getOwnerUserId()): StoredCard {
  const isOwner = row.userId === viewerId;
  const savedPinAt = saves.pins.get(row.id);
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

  const isPinned = isOwner ? row.isPinned : savedPinAt !== undefined;
  const pinnedAt = isOwner ? row.pinnedAt : savedPinAt;

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
    isPinned,
    isPublic: row.isPublic,
    createdAt: row.createdAt.toISOString(),
    isOwner,
    author: { initials: row.user.initials },
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
  if (pinnedAt) {
    stored.pinnedAt = pinnedAt.toISOString();
  }

  return stored;
}
