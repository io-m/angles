import { describe, expect, it } from "vitest";
import { CATEGORIES, STYLES, type Category } from "../types/index.js";
import {
  SHAPE,
  mulberry32,
  planPosts,
  planReaders,
  planViewerHearts,
  type HeartableCard,
  type PostInput,
} from "./communityShape.js";

const NOW = new Date("2026-09-30T08:00:00.000Z");
const HOUR = 3_600_000;
const DAY = 24 * HOUR;

const posts: PostInput[] = Array.from({ length: 330 }, (_, index) => ({
  id: `00000000-0000-4000-8200-${String(index + 1).padStart(12, "0")}`,
  category: CATEGORIES[index % CATEGORIES.length] as Category,
}));
const authors = Array.from({ length: 50 }, (_, index) => `author-${index}`);

function plan(seed = 7) {
  return planPosts(posts, authors, NOW, mulberry32(seed));
}

describe("community post shape", () => {
  it("is reproducible for one seed and different for another", () => {
    expect(plan(7)).toEqual(plan(7));
    expect(plan(7)).not.toEqual(plan(8));
  });

  it("gives every post exactly one slot, none in the future", () => {
    const planned = plan();
    expect(planned).toHaveLength(posts.length);
    expect(new Set(planned.map((item) => item.id)).size).toBe(posts.length);
    expect(planned.every((item) => item.createdAt.getTime() <= NOW.getTime())).toBe(true);
  });

  it("puts a busy day at the head, a few posts inside two hours, and a tail behind it", () => {
    const ages = plan().map((item) => NOW.getTime() - item.createdAt.getTime());
    expect(ages.filter((age) => age < DAY)).toHaveLength(SHAPE.lastDay);
    expect(ages.filter((age) => age < 2 * HOUR).length).toBeGreaterThanOrEqual(SHAPE.justPosted);
    expect(Math.max(...ages)).toBeLessThanOrEqual(SHAPE.spanDays * DAY);
    expect(ages.filter((age) => age >= 2 * DAY && age < 3 * DAY).length).toBeGreaterThan(2);
  });

  it("makes some authors prolific and most quiet, with everyone posting", () => {
    const counts = new Map<string, number>();
    for (const item of plan()) {
      counts.set(item.userId, (counts.get(item.userId) ?? 0) + 1);
    }
    expect(counts.size).toBe(authors.length);
    const sorted = [...counts.values()].sort((left, right) => right - left);
    expect(sorted[0]).toBeGreaterThan(15);
    expect(sorted[0]).toBeLessThanOrEqual(SHAPE.maxPerAuthor);
    expect(sorted.filter((count) => count <= 3).length).toBeGreaterThan(10);
  });

  it("lets trending themes land nearer to now than trailing ones", () => {
    const meanAge = (category: Category): number => {
      const ages = plan()
        .filter((item) => posts.find((post) => post.id === item.id)?.category === category)
        .map((item) => NOW.getTime() - item.createdAt.getTime());
      return ages.reduce((sum, age) => sum + age, 0) / ages.length;
    };
    expect(meanAge("work")).toBeLessThan(meanAge("grief_loss"));
  });

  it("skews intensity to the middle", () => {
    const counts = [0, 0, 0, 0, 0, 0];
    for (const item of plan()) {
      counts[item.intensity] = (counts[item.intensity] ?? 0) + 1;
    }
    expect(counts[3]).toBeGreaterThan(counts[1] ?? 0);
    expect(counts[3]).toBeGreaterThan(counts[5] ?? 0);
  });
});

describe("community readers", () => {
  const planned = plan();
  const cards: HeartableCard[] = planned.map((item) => ({
    id: item.id,
    category: posts.find((post) => post.id === item.id)?.category ?? "work",
    createdAt: item.createdAt,
    styles: STYLES,
  }));

  it("hearts after a post lands, never in the future, once per angle", () => {
    const readers = planReaders(cards, NOW, mulberry32(3));
    const byId = new Map(cards.map((card) => [card.id, card]));
    const seen = new Set<string>();
    for (const reader of readers) {
      for (const heart of reader.hearts) {
        const card = byId.get(heart.cardId);
        expect(heart.favoritedAt.getTime()).toBeGreaterThan(card?.createdAt.getTime() ?? Infinity);
        expect(heart.favoritedAt.getTime()).toBeLessThan(NOW.getTime());
        const key = `${heart.userId}:${heart.cardId}:${heart.style}`;
        expect(seen.has(key)).toBe(false);
        seen.add(key);
      }
    }
  });

  it("leaves most posts unloved and a few adored", () => {
    const readers = planReaders(cards, NOW, mulberry32(3));
    const perCard = new Map<string, number>();
    for (const reader of readers) {
      for (const heart of reader.hearts) {
        perCard.set(heart.cardId, (perCard.get(heart.cardId) ?? 0) + 1);
      }
    }
    const unloved = cards.filter((card) => !perCard.has(card.id)).length;
    expect(unloved / cards.length).toBeGreaterThan(0.35);
    expect(Math.max(...perCard.values())).toBeGreaterThanOrEqual(8);
  });

  it("gives readers different tastes", () => {
    const readers = planReaders(cards, NOW, mulberry32(3));
    expect(readers).toHaveLength(SHAPE.readers);
    expect(new Set(readers.map((reader) => reader.style)).size).toBeGreaterThan(2);
    expect(new Set(readers.flatMap((reader) => reader.categories)).size).toBeGreaterThan(4);
  });

  it("plans a small themed history for the viewer, hearted recently", () => {
    const hearts = planViewerHearts("viewer", cards, NOW, mulberry32(5));
    expect(hearts.length).toBeGreaterThan(3);
    expect(hearts.length).toBeLessThanOrEqual(8);
    const byId = new Map(cards.map((card) => [card.id, card]));
    for (const heart of hearts) {
      expect(["work", "self_worth"]).toContain(byId.get(heart.cardId)?.category);
      expect(["stoic", "tough_love"]).toContain(heart.style);
      expect(NOW.getTime() - heart.favoritedAt.getTime()).toBeLessThanOrEqual(3 * DAY);
      expect(heart.favoritedAt.getTime()).toBeGreaterThan(byId.get(heart.cardId)?.createdAt.getTime() ?? Infinity);
    }
  });
});
