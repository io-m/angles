import { describe, expect, it } from "vitest";
import { CATEGORIES, STYLES, type Category } from "../types/index.js";
import {
  SHAPE,
  mulberry32,
  planPosts,
  planReaders,
  planViewerDecisions,
  type DecidableCard,
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
  const cards: DecidableCard[] = planned.map((item) => ({
    id: item.id,
    category: posts.find((post) => post.id === item.id)?.category ?? "work",
    createdAt: item.createdAt,
    styles: STYLES,
  }));

  it("decides after a post lands, never in the future, once per reader and card", () => {
    const readers = planReaders(cards, NOW, mulberry32(3));
    const byId = new Map(cards.map((card) => [card.id, card]));
    const seen = new Set<string>();
    for (const reader of readers) {
      for (const decision of reader.decisions) {
        const card = byId.get(decision.cardId);
        expect(decision.decidedAt.getTime()).toBeGreaterThan(card?.createdAt.getTime() ?? Infinity);
        expect(decision.decidedAt.getTime()).toBeLessThan(NOW.getTime());
        expect(decision.checkedStyles).toContain(decision.style);
        expect(decision.passes).toBe(decision.kind === "pass" ? 1 : 0);
        const key = `${decision.userId}:${decision.cardId}`;
        expect(seen.has(key)).toBe(false);
        seen.add(key);
      }
    }
  });

  it("leaves most posts unsaved and a few adored, and passes more than it saves", () => {
    const readers = planReaders(cards, NOW, mulberry32(3));
    const perCard = new Map<string, number>();
    let saves = 0;
    let passes = 0;
    for (const reader of readers) {
      for (const decision of reader.decisions) {
        if (decision.kind === "save") {
          saves += 1;
          perCard.set(decision.cardId, (perCard.get(decision.cardId) ?? 0) + 1);
        } else {
          passes += 1;
        }
      }
    }
    const unloved = cards.filter((card) => !perCard.has(card.id)).length;
    expect(unloved / cards.length).toBeGreaterThan(0.35);
    expect(Math.max(...perCard.values())).toBeGreaterThanOrEqual(8);
    expect(passes).toBeGreaterThan(saves);
  });

  it("gives readers different tastes", () => {
    const readers = planReaders(cards, NOW, mulberry32(3));
    expect(readers).toHaveLength(SHAPE.readers);
    expect(new Set(readers.map((reader) => reader.style)).size).toBeGreaterThan(2);
    expect(new Set(readers.flatMap((reader) => reader.categories)).size).toBeGreaterThan(4);
  });

  it("plans a small themed history for the viewer, saved recently, with a few passes elsewhere", () => {
    const decisions = planViewerDecisions("viewer", cards, NOW, mulberry32(5));
    const saves = decisions.filter((decision) => decision.kind === "save");
    expect(saves.length).toBeGreaterThan(3);
    expect(saves.length).toBeLessThanOrEqual(8);
    const byId = new Map(cards.map((card) => [card.id, card]));
    for (const decision of decisions) {
      const category = byId.get(decision.cardId)?.category;
      if (decision.kind === "save") {
        expect(["work", "self_worth"]).toContain(category);
        expect(["stoic", "tough"]).toContain(decision.style);
      } else {
        expect(["work", "self_worth"]).not.toContain(category);
      }
      expect(NOW.getTime() - decision.decidedAt.getTime()).toBeLessThanOrEqual(3 * DAY);
      expect(decision.decidedAt.getTime()).toBeGreaterThan(byId.get(decision.cardId)?.createdAt.getTime() ?? Infinity);
    }
  });
});
