import { beforeEach, describe, expect, it, vi } from "vitest";
import { STYLES, type StoredCard } from "../types/index.js";

vi.mock("../db/client.js", () => {
  class DbError extends Error {
    readonly code?: string;
    constructor(message: string, code?: string) {
      super(message);
      this.name = "DbError";
      this.code = code;
    }
  }
  return {
    probeDatabase: vi.fn(async () => "ok" as const),
    DbError,
    getDb: vi.fn(),
    getSql: vi.fn(),
    closePool: vi.fn(),
    assertSchemaCurrent: vi.fn(),
    wrapDbError: vi.fn(),
  };
});

vi.mock("../db/cards.js", () => ({
  createCard: vi.fn(),
  listCards: vi.fn(),
  getCard: vi.fn(),
  patchCard: vi.fn(),
  deleteCard: vi.fn(),
}));

vi.mock("../db/feed.js", () => ({
  listFeed: vi.fn(),
  listHomeFeed: vi.fn(),
  pinFeedCard: vi.fn(),
  unpinFeedCard: vi.fn(),
  saveFeedAngle: vi.fn(),
  unsaveFeedAngle: vi.fn(),
  clearFeedSaves: vi.fn(),
}));

const { createApp } = await import("../app.js");
const { listFeed, listHomeFeed, pinFeedCard, saveFeedAngle, clearFeedSaves } = await import(
  "../db/feed.js"
);

const app = createApp();
const CARD_ID = "22222222-2222-4222-8222-222222222222";

function feedCard(overrides: Partial<StoredCard> = {}): StoredCard {
  return {
    id: CARD_ID,
    thought: "I keep waiting for a reply that is not coming and I feel small.",
    inputLanguage: "en",
    category: "work",
    tags: [{ slug: "waiting", label: "Waiting" }],
    intensity: 4,
    intensityBand: "high",
    timeframe: "ongoing",
    emotions: ["shame", "fear"],
    safety: "none",
    skippedStyles: [],
    matching: { category: "work", tags: ["waiting"], intensityBand: "high" },
    results: STYLES.map((style) => ({ style, reframe: `A ${style} take.`, isFavorite: false })),
    model: "mistral-small-latest",
    spotlightStyle: "optimistic",
    isPinned: false,
    isPublic: true,
    createdAt: "2026-09-10T12:00:00.000Z",
    isOwner: false,
    author: { initials: "AL" },
    ...overrides,
  };
}

async function jsonOf(response: Response): Promise<unknown> {
  return response.json();
}

describe("GET /feed", () => {
  beforeEach(() => {
    vi.mocked(listFeed).mockReset();
  });

  it("lists public cards newest first", async () => {
    const card = feedCard();
    vi.mocked(listFeed).mockResolvedValue([card]);

    const response = await app.request("/feed");
    expect(response.status).toBe(200);
    await expect(jsonOf(response)).resolves.toEqual({ cards: [card] });
    expect(listFeed).toHaveBeenCalledWith({
      limit: 200,
      before: undefined,
      category: undefined,
      style: undefined,
      emotion: undefined,
    });
  });

  it("passes style, category, and emotion filters", async () => {
    vi.mocked(listFeed).mockResolvedValue([]);
    const response = await app.request("/feed?style=stoic&category=work&emotion=shame&limit=10");
    expect(response.status).toBe(200);
    expect(listFeed).toHaveBeenCalledWith({
      limit: 10,
      before: undefined,
      category: "work",
      style: "stoic",
      emotion: "shame",
    });
  });
});

describe("GET /feed/home", () => {
  beforeEach(() => {
    vi.mocked(listHomeFeed).mockReset();
  });

  it("returns the grouped shelves with six cards per shelf by default", async () => {
    const card = feedCard();
    vi.mocked(listHomeFeed).mockResolvedValue({
      cards: [card],
      recent: [card.id],
      sections: [{ kind: "category", id: "work", cardIds: [card.id] }],
    });

    const response = await app.request("/feed/home");
    expect(response.status).toBe(200);
    await expect(jsonOf(response)).resolves.toEqual({
      cards: [card],
      recent: [card.id],
      sections: [{ kind: "category", id: "work", cardIds: [card.id] }],
    });
    expect(listHomeFeed).toHaveBeenCalledWith({ style: undefined, perSection: 6 });
  });

  it("passes the style filter through so capped shelves stay full", async () => {
    vi.mocked(listHomeFeed).mockResolvedValue({ cards: [], recent: [], sections: [] });

    const response = await app.request("/feed/home?style=stoic&perSection=3");
    expect(response.status).toBe(200);
    expect(listHomeFeed).toHaveBeenCalledWith({ style: "stoic", perSection: 3 });
  });

  it("rejects an unknown style", async () => {
    const response = await app.request("/feed/home?style=zen");
    expect(response.status).toBe(400);
    await expect(jsonOf(response)).resolves.toMatchObject({ code: "VALIDATION_ERROR" });
    expect(listHomeFeed).not.toHaveBeenCalled();
  });
});

describe("PUT /feed/cards/:id/pin", () => {
  beforeEach(() => {
    vi.mocked(pinFeedCard).mockReset();
  });

  it("returns the viewer-scoped card", async () => {
    const card = feedCard({ isPinned: true });
    vi.mocked(pinFeedCard).mockResolvedValue({ ok: true, card });
    const response = await app.request(`/feed/cards/${CARD_ID}/pin`, { method: "PUT" });
    expect(response.status).toBe(200);
    await expect(jsonOf(response)).resolves.toEqual(card);
  });

  it("returns 404 when the card is not a public other", async () => {
    vi.mocked(pinFeedCard).mockResolvedValue({ ok: false, reason: "not_found" });
    const response = await app.request(`/feed/cards/${CARD_ID}/pin`, { method: "PUT" });
    expect(response.status).toBe(404);
    await expect(jsonOf(response)).resolves.toEqual({ error: "Not found", code: "NOT_FOUND" });
  });
});

describe("PUT /feed/cards/:id/angles/:style", () => {
  beforeEach(() => {
    vi.mocked(saveFeedAngle).mockReset();
  });

  it("returns 400 when the style is not on the card", async () => {
    vi.mocked(saveFeedAngle).mockResolvedValue({ ok: false, reason: "unknown_style" });
    const response = await app.request(`/feed/cards/${CARD_ID}/angles/stoic`, { method: "PUT" });
    expect(response.status).toBe(400);
    await expect(jsonOf(response)).resolves.toMatchObject({ code: "VALIDATION_ERROR" });
  });
});

describe("DELETE /feed/cards/:id/saves", () => {
  beforeEach(() => {
    vi.mocked(clearFeedSaves).mockReset();
  });

  it("returns 204", async () => {
    vi.mocked(clearFeedSaves).mockResolvedValue({ ok: true, card: feedCard() });
    const response = await app.request(`/feed/cards/${CARD_ID}/saves`, { method: "DELETE" });
    expect(response.status).toBe(204);
  });
});
