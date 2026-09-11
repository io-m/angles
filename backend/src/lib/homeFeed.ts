import {
  CATEGORIES,
  EMOTIONS,
  type FeedHomeResponse,
  type FeedHomeSection,
  type StoredCard,
} from "../types/index.js";

/**
 * Groups a newest-first card scan into the Home shelves: Recent, one per life-domain
 * category, one per mood. Every shelf is capped at `perSection` and empty shelves are
 * dropped, so the client renders exactly what it receives. Cards are returned once even
 * though a card belongs to one domain and several moods.
 */
export function groupHomeFeed(cards: StoredCard[], perSection: number): FeedHomeResponse {
  const recent: string[] = [];
  const byCategory = new Map<string, string[]>();
  const byEmotion = new Map<string, string[]>();
  const used = new Set<string>();
  const unique: StoredCard[] = [];

  const keep = (card: StoredCard): void => {
    if (used.has(card.id)) {
      return;
    }
    used.add(card.id);
    unique.push(card);
  };

  const push = (buckets: Map<string, string[]>, key: string, card: StoredCard): void => {
    let bucket = buckets.get(key);
    if (!bucket) {
      bucket = [];
      buckets.set(key, bucket);
    }
    if (bucket.length >= perSection) {
      return;
    }
    bucket.push(card.id);
    keep(card);
  };

  for (const card of cards) {
    if (recent.length < perSection) {
      recent.push(card.id);
      keep(card);
    }

    push(byCategory, card.category, card);
    for (const emotion of new Set(card.emotions)) {
      push(byEmotion, emotion, card);
    }
  }

  const sections: FeedHomeSection[] = [];
  for (const category of CATEGORIES) {
    const cardIds = byCategory.get(category);
    if (cardIds && cardIds.length > 0) {
      sections.push({ kind: "category", id: category, cardIds });
    }
  }
  for (const emotion of EMOTIONS) {
    const cardIds = byEmotion.get(emotion);
    if (cardIds && cardIds.length > 0) {
      sections.push({ kind: "emotion", id: emotion, cardIds });
    }
  }

  return { cards: unique, recent, sections };
}
