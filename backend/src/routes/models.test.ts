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

vi.mock("../db/feed.js", () => ({
  listFeed: vi.fn(),
  listPublicCardsForUser: vi.fn(),
  listPublicCardsForModel: vi.fn(),
  saveFeedAngle: vi.fn(),
  unsaveFeedAngle: vi.fn(),
  clearFeedSaves: vi.fn(),
}));

const { createApp } = await import("../app.js");
const { listPublicCardsForModel } = await import("../db/feed.js");

const app = createApp();
const CARD_A = "22222222-2222-4222-8222-222222222222";
const CARD_B = "33333333-3333-4333-8333-333333333333";
const MISTRAL = "mistral-small-latest";

function publicCard(overrides: Partial<StoredCard> = {}): StoredCard {
  return {
    id: CARD_A,
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
    model: MISTRAL,
    spotlightStyle: "optimistic",
    isPublic: true,
    createdAt: "2026-09-10T12:00:00.000Z",
    isOwner: false,
    author: {
      id: "00000000-0000-4000-8000-000000000099",
      initials: "AL",
      following: false,
    },
    ...overrides,
  };
}

async function jsonOf(response: Response): Promise<unknown> {
  return response.json();
}

describe("GET /models/:id/cards", () => {
  beforeEach(() => {
    vi.mocked(listPublicCardsForModel).mockReset();
    vi.mocked(listPublicCardsForModel).mockResolvedValue([]);
  });

  it("returns public cards cooked by that model", async () => {
    const card = publicCard();
    vi.mocked(listPublicCardsForModel).mockResolvedValue([card]);

    const response = await app.request(`/models/${MISTRAL}/cards`);
    expect(response.status).toBe(200);
    await expect(jsonOf(response)).resolves.toEqual({ model: MISTRAL, cards: [card] });
    expect(listPublicCardsForModel).toHaveBeenCalledWith({
      model: MISTRAL,
      limit: 24,
      before: undefined,
    });
  });

  it("returns an empty page when that model has no public cards", async () => {
    const response = await app.request("/models/gemini-3.8-flash/cards");
    expect(response.status).toBe(200);
    await expect(jsonOf(response)).resolves.toEqual({
      model: "gemini-3.8-flash",
      cards: [],
    });
    expect(listPublicCardsForModel).toHaveBeenCalledWith({
      model: "gemini-3.8-flash",
      limit: 24,
      before: undefined,
    });
  });

  it("pages with the composite cursor and does not repeat the boundary card", async () => {
    const older = publicCard({
      id: CARD_B,
      createdAt: "2026-09-09T12:00:00.000Z",
    });
    vi.mocked(listPublicCardsForModel).mockResolvedValue([older]);
    const before = `2026-09-10T12:00:00.000Z|${CARD_A}`;

    const response = await app.request(
      `/models/${MISTRAL}/cards?before=${encodeURIComponent(before)}&limit=24`,
    );
    expect(response.status).toBe(200);
    const body = (await jsonOf(response)) as { cards: StoredCard[] };
    expect(body.cards.map((card) => card.id)).toEqual([CARD_B]);
    expect(body.cards.some((card) => card.id === CARD_A)).toBe(false);
    expect(listPublicCardsForModel).toHaveBeenCalledWith({
      model: MISTRAL,
      limit: 24,
      before: { createdAt: new Date("2026-09-10T12:00:00.000Z"), id: CARD_A },
    });
  });

  it.each([
    "/models/not-a-model/cards",
    "/models/deepseek-v4/cards",
    `/models/${MISTRAL}/cards?style=stoic`,
    `/models/${MISTRAL}/cards?categories=work`,
    `/models/${MISTRAL}/cards?before=not-a-cursor`,
  ])("rejects %s", async (path) => {
    const response = await app.request(path);
    expect(response.status).toBe(400);
    await expect(jsonOf(response)).resolves.toMatchObject({ code: "VALIDATION_ERROR" });
    expect(listPublicCardsForModel).not.toHaveBeenCalled();
  });
});
