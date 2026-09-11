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
  saveFeedAngle: vi.fn(),
  unsaveFeedAngle: vi.fn(),
  clearFeedSaves: vi.fn(),
}));

const { createApp } = await import("../app.js");
const { listFeed, saveFeedAngle, clearFeedSaves } = await import("../db/feed.js");

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
      categories: undefined,
      emotions: undefined,
    });
  });

  it("passes several categories in catalog order", async () => {
    vi.mocked(listFeed).mockResolvedValue([]);
    const response = await app.request("/feed?categories=money,work,money&limit=10");
    expect(response.status).toBe(200);
    expect(listFeed).toHaveBeenCalledWith({
      limit: 10,
      before: undefined,
      categories: ["work", "money"],
      emotions: undefined,
    });
  });

  it("passes several emotions in catalog order", async () => {
    vi.mocked(listFeed).mockResolvedValue([]);
    const response = await app.request("/feed?emotions=overwhelm,fear");
    expect(response.status).toBe(200);
    expect(listFeed).toHaveBeenCalledWith({
      limit: 200,
      before: undefined,
      categories: undefined,
      emotions: ["fear", "overwhelm"],
    });
  });

  it("combines category and emotion groups", async () => {
    vi.mocked(listFeed).mockResolvedValue([]);
    const response = await app.request("/feed?categories=work,money&emotions=fear,overwhelm");
    expect(response.status).toBe(200);
    expect(listFeed).toHaveBeenCalledWith({
      limit: 200,
      before: undefined,
      categories: ["work", "money"],
      emotions: ["fear", "overwhelm"],
    });
  });

  it("decodes the composite keyset cursor", async () => {
    vi.mocked(listFeed).mockResolvedValue([]);
    const before = `2026-09-10T12:00:00.000Z|${CARD_ID}`;
    const response = await app.request(`/feed?before=${encodeURIComponent(before)}`);
    expect(response.status).toBe(200);
    expect(listFeed).toHaveBeenCalledWith({
      limit: 200,
      before: { createdAt: new Date("2026-09-10T12:00:00.000Z"), id: CARD_ID },
      categories: undefined,
      emotions: undefined,
    });
  });

  it.each([
    "/feed?categories=work,unknown",
    "/feed?categories=work,",
    "/feed?emotions=fear,calm",
    "/feed?before=not-a-cursor",
    "/feed?style=stoic",
    "/feed?category=work",
    "/feed?emotion=fear",
  ])("rejects invalid or removed query values: %s", async (path) => {
    const response = await app.request(path);
    expect(response.status).toBe(400);
    await expect(jsonOf(response)).resolves.toMatchObject({ code: "VALIDATION_ERROR" });
    expect(listFeed).not.toHaveBeenCalled();
  });

  it("404s the retired grouped Home route", async () => {
    const response = await app.request("/feed/home");
    expect(response.status).toBe(404);
  });
});

describe("PUT /feed/cards/:id/angles/:style", () => {
  beforeEach(() => {
    vi.mocked(saveFeedAngle).mockReset();
  });

  it("returns the viewer-scoped card", async () => {
    const card = feedCard({
      results: STYLES.map((style) => ({
        style,
        reframe: `A ${style} take.`,
        isFavorite: style === "stoic",
      })),
    });
    vi.mocked(saveFeedAngle).mockResolvedValue({ ok: true, card });
    const response = await app.request(`/feed/cards/${CARD_ID}/angles/stoic`, { method: "PUT" });
    expect(response.status).toBe(200);
    await expect(jsonOf(response)).resolves.toEqual(card);
  });

  it("returns 404 when the card is not a public other", async () => {
    vi.mocked(saveFeedAngle).mockResolvedValue({ ok: false, reason: "not_found" });
    const response = await app.request(`/feed/cards/${CARD_ID}/angles/stoic`, { method: "PUT" });
    expect(response.status).toBe(404);
    await expect(jsonOf(response)).resolves.toEqual({ error: "Not found", code: "NOT_FOUND" });
  });

  it("returns 400 when the style is not on the card", async () => {
    vi.mocked(saveFeedAngle).mockResolvedValue({ ok: false, reason: "unknown_style" });
    const response = await app.request(`/feed/cards/${CARD_ID}/angles/stoic`, { method: "PUT" });
    expect(response.status).toBe(400);
    await expect(jsonOf(response)).resolves.toMatchObject({ code: "VALIDATION_ERROR" });
  });

  it("404s the removed pin route", async () => {
    const response = await app.request(`/feed/cards/${CARD_ID}/pin`, { method: "PUT" });
    expect(response.status).toBe(404);
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
