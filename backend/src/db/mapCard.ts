import { getOwnerUserId } from "../lib/authStub.js";
import { avatarUrlFor } from "../lib/avatarUrl.js";
import { openingStyle } from "../lib/feedRanking.js";
import { isStyleShown } from "../lib/styleSet.js";
import { intensityBand, type StoredCard, type StoredReframeResult, type Style } from "../types/index.js";
import { getDb } from "./client.js";
import { loadViewerDecisions, toCardDecision } from "./decisions.js";
import { followedAuthorIds } from "./follows.js";
import { loadSaveCountsByStyle, loadViewerSavedStyle } from "./saves.js";
import type { CardDecisionRow, CardReframeRow, CardRow, TagRow, UserRow } from "./schema.js";

type Selectable = Pick<ReturnType<typeof getDb>, "select">;

export type CardLoaded = CardRow & {
  reframes: CardReframeRow[];
  cardTags: { tag: TagRow }[];
  user: Pick<UserRow, "initials" | "avatarKey" | "kind">;
};

/** Everything about the viewer that shapes how a card reads for them. */
export type CardViewContext = {
  viewerId: string;
  decisions: ReadonlyMap<string, CardDecisionRow>;
  followed: ReadonlySet<string>;
  /** Saves per angle, for the viewer's own public cards only. */
  saveCounts: ReadonlyMap<string, ReadonlyMap<Style, number>>;
  /** The angle this viewer most often saves on. */
  preferredStyle: Style | null;
};

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
  loaded: CardLoaded[],
  viewerId: string = getOwnerUserId(),
  db: Selectable = getDb(),
  /** A ranked visit passes what it read at its start, so every page opens cards alike. */
  options: { followed?: ReadonlySet<string>; preferredStyle?: Style | null } = {},
): Promise<StoredCard[]> {
  // An app that cannot show any of a card's angles would fail to decode it; it never sees it.
  const rows = loaded.filter((row) => row.reframes.some((item) => isStyleShown(item.style)));
  const ownPublicIds = rows
    .filter((row) => row.userId === viewerId && row.isPublic)
    .map((row) => row.id);
  const othersIds = rows.filter((row) => row.userId !== viewerId).map((row) => row.id);
  const [decisions, followed, saveCounts, preferredStyle] = await Promise.all([
    loadViewerDecisions(othersIds, viewerId, db),
    options.followed
      ? Promise.resolve(new Set(options.followed))
      : followedAuthorIds(
          viewerId,
          rows.map((row) => row.userId),
          db,
        ),
    // Only ever queried for the viewer's own published cards, so there is nothing to
    // leak even if a later caller forgets the owner check below.
    loadSaveCountsByStyle(ownPublicIds, db),
    options.preferredStyle !== undefined
      ? Promise.resolve(options.preferredStyle)
      : othersIds.length > 0
        ? loadViewerSavedStyle(viewerId, db)
        : Promise.resolve(null),
  ]);
  const context: CardViewContext = { viewerId, decisions, followed, saveCounts, preferredStyle };
  return rows.map((row) => toStoredCard(row, context));
}

function shownCover(cover: Style, results: readonly StoredReframeResult[]): Style {
  return results.some((item) => item.style === cover) ? cover : (results[0]?.style ?? cover);
}

export function toStoredCard(row: CardLoaded, context: CardViewContext): StoredCard {
  const isOwner = row.userId === context.viewerId;
  const decision = isOwner ? undefined : context.decisions.get(row.id);
  const ownSaves = isOwner && row.isPublic ? context.saveCounts.get(row.id) : undefined;
  const tagList = row.cardTags.map((join) => ({
    slug: join.tag.slug,
    label: join.tag.label,
  }));
  // The calling app's styles only: an older build fails a card on a style it does not know.
  const results: StoredReframeResult[] = row.reframes
    .filter((item) => isStyleShown(item.style))
    .sort((left, right) => left.position - right.position)
    .map((item) => {
      const stored: StoredReframeResult = { style: item.style, reframe: item.reframe };
      if (!isOwner) {
        return stored;
      }
      // The public card is English; only its author reads the answer in their language.
      if (item.reframeOriginal) {
        stored.reframeOriginal = item.reframeOriginal;
      }
      // Absent at zero: a 0 on a post you just published about your worst day is
      // worse than no number at all.
      const saves = ownSaves?.get(item.style);
      if (saves !== undefined && saves > 0) {
        stored.saveCount = saves;
      }
      return stored;
    });

  const available = results.map((item) => item.style);
  const cover = shownCover(row.spotlightStyle, results);
  let opening = cover;
  if (!isOwner) {
    if (decision?.kind === "save" && available.includes(decision.style)) {
      opening = decision.style;
    } else {
      opening = openingStyle({
        cardId: row.id,
        viewerId: context.viewerId,
        cover,
        available,
        preferred: context.preferredStyle,
        checked: decision?.kind === "pass" ? new Set(decision.checkedStyles) : undefined,
      });
    }
  }

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
    skippedStyles: row.skippedStyles.filter((item) => isStyleShown(item.style)),
    matching: {
      category: row.category,
      tags: tagList.map((tag) => tag.slug),
      intensityBand: intensityBand(row.intensity),
    },
    results,
    model: row.model,
    spotlightStyle: cover,
    openingStyle: opening,
    isPublic: row.isPublic,
    createdAt: row.createdAt.toISOString(),
    isOwner,
    isHouse: row.user.kind === "house",
    author: authorOf(
      row.userId,
      row.user,
      !isOwner && row.user.kind !== "house" && context.followed.has(row.userId),
    ),
  };

  if (decision) {
    stored.decision = toCardDecision(decision);
  }
  if (ownSaves) {
    let total = 0;
    for (const saves of ownSaves.values()) {
      total += saves;
    }
    if (total > 0) {
      stored.saveCount = total;
    }
  }
  if (isOwner && !row.isPublic && row.moderationHiddenAt) {
    stored.moderationHidden = true;
  }
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
