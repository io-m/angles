import { describe, expect, it } from "vitest";
import { STYLES, type Category, type Emotion, type StoredCard } from "../types/index.js";
import { groupHomeFeed } from "./homeFeed.js";

function card(id: string, category: Category, emotions: Emotion[]): StoredCard {
  return {
    id,
    thought: "A thought that fits a card.",
    inputLanguage: "en",
    category,
    tags: [],
    intensity: 3,
    intensityBand: "mid",
    timeframe: "ongoing",
    emotions,
    safety: "none",
    skippedStyles: [],
    matching: { category, tags: [], intensityBand: "mid" },
    results: STYLES.map((style) => ({ style, reframe: `A ${style} take.`, isFavorite: false })),
    model: "mistral-small-latest",
    spotlightStyle: "stoic",
    isPinned: false,
    isPublic: true,
    createdAt: "2026-09-10T12:00:00.000Z",
    isOwner: false,
    author: { initials: "AL" },
  };
}

describe("groupHomeFeed", () => {
  it("caps recent and every shelf at perSection", () => {
    const cards = Array.from({ length: 10 }, (_, index) => card(`card-${index}`, "work", ["anger"]));

    const home = groupHomeFeed(cards, 6);

    expect(home.recent).toHaveLength(6);
    expect(home.sections).toHaveLength(2);
    for (const section of home.sections) {
      expect(section.cardIds).toHaveLength(6);
    }
  });

  it("lists each card once even when several shelves hold it", () => {
    const home = groupHomeFeed([card("a", "money", ["shame", "fear"])], 6);

    expect(home.cards.map((item) => item.id)).toEqual(["a"]);
    expect(home.recent).toEqual(["a"]);
    expect(home.sections).toEqual([
      { kind: "category", id: "money", cardIds: ["a"] },
      { kind: "emotion", id: "shame", cardIds: ["a"] },
      { kind: "emotion", id: "fear", cardIds: ["a"] },
    ]);
  });

  it("drops empty shelves and keeps catalog order per kind", () => {
    const home = groupHomeFeed(
      [card("a", "health", ["hope"]), card("b", "work", ["anger"])],
      6,
    );

    expect(home.sections.map((section) => `${section.kind}:${section.id}`)).toEqual([
      "category:work",
      "category:health",
      "emotion:anger",
      "emotion:hope",
    ]);
  });

  it("only carries cards that a shelf references", () => {
    const cards = Array.from({ length: 8 }, (_, index) => card(`card-${index}`, "work", ["anger"]));

    const home = groupHomeFeed(cards, 3);

    expect(home.cards.map((item) => item.id)).toEqual(["card-0", "card-1", "card-2"]);
  });

  it("returns no sections for an empty scan", () => {
    expect(groupHomeFeed([], 6)).toEqual({ cards: [], recent: [], sections: [] });
  });
});
