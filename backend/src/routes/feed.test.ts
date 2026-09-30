import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
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
  hasPublicationReportLock: vi.fn(),
  patchCard: vi.fn(),
  deleteCard: vi.fn(),
}));

vi.mock("../db/feed.js", () => ({
  listFeed: vi.fn(),
  listRankedFeed: vi.fn(),
  listPublicCardsForUser: vi.fn(),
  listPublicCardsForModel: vi.fn(),
  saveFeedAngle: vi.fn(),
  unsaveFeedAngle: vi.fn(),
  clearFeedSaves: vi.fn(),
}));

const { createApp } = await import("../app.js");
const { listFeed, listRankedFeed, saveFeedAngle, clearFeedSaves } = await import("../db/feed.js");
const { decodeFeedSession, encodeFeedSession } = await import("../lib/feedRanking.js");

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
    author: { id: "00000000-0000-4000-8000-000000000099", initials: "AL", following: false },
    ...overrides,
  };
}

async function jsonOf(response: Response): Promise<unknown> {
  return response.json();
}

describe("GET /feed", () => {
  beforeEach(() => {
    vi.mocked(listFeed).mockReset();
    // The developer's .env turns ranking on; these tests are about the unranked path.
    delete process.env.FEED_RANKING;
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
      style: undefined,
    });
  });

  it("passes a style filter", async () => {
    vi.mocked(listFeed).mockResolvedValue([]);
    const response = await app.request("/feed?style=stoic&limit=24");
    expect(response.status).toBe(200);
    expect(listFeed).toHaveBeenCalledWith({
      limit: 24,
      before: undefined,
      categories: undefined,
      emotions: undefined,
      style: "stoic",
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
      style: undefined,
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
      style: undefined,
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
      style: undefined,
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
      style: undefined,
    });
  });

  it("asks for arrivals with the composite cursor", async () => {
    vi.mocked(listFeed).mockResolvedValue([]);
    const after = `2026-09-10T12:00:00.000Z|${CARD_ID}`;
    const response = await app.request(`/feed?after=${encodeURIComponent(after)}&limit=8`);
    expect(response.status).toBe(200);
    expect(listFeed).toHaveBeenCalledWith({
      limit: 8,
      before: undefined,
      after: { createdAt: new Date("2026-09-10T12:00:00.000Z"), id: CARD_ID },
      categories: undefined,
      emotions: undefined,
      style: undefined,
    });
  });

  it.each([
    "/feed?categories=work,unknown",
    "/feed?categories=work,",
    "/feed?emotions=fear,calm",
    "/feed?before=not-a-cursor",
    "/feed?after=not-a-cursor",
    `/feed?before=2026-09-10T12:00:00.000Z|${CARD_ID}&after=2026-09-10T12:00:00.000Z|${CARD_ID}`,
    "/feed?style=unknown",
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

describe("GET /feed with resonance ranking", () => {
  beforeEach(() => {
    vi.mocked(listFeed).mockReset();
    vi.mocked(listRankedFeed).mockReset();
    process.env.FEED_RANKING = "resonance";
  });

  afterEach(() => {
    delete process.env.FEED_RANKING;
  });

  it("mints a session and hands back its cursor", async () => {
    vi.mocked(listRankedFeed).mockResolvedValue([feedCard()]);
    const before = new Date();
    const response = await app.request("/feed?limit=24");
    expect(response.status).toBe(200);

    const body = (await jsonOf(response)) as { cards: unknown[]; page: { nextCursor: string } };
    expect(body.cards).toHaveLength(1);
    expect(listFeed).not.toHaveBeenCalled();

    const minted = vi.mocked(listRankedFeed).mock.calls[0]?.[0].session;
    expect(minted?.offset).toBe(0);
    expect(minted?.seed).toMatch(/^[A-Za-z0-9_-]{8,64}$/);
    expect(minted?.startedAt.getTime()).toBeGreaterThanOrEqual(before.getTime());

    // The next page starts where this one ended, on the same frozen candidate set.
    const next = decodeFeedSession(body.page.nextCursor);
    expect(next).toEqual({ seed: minted?.seed, startedAt: minted?.startedAt, offset: 1 });
  });

  it("keeps a style on the ranked request and on the next page", async () => {
    vi.mocked(listRankedFeed).mockResolvedValue([feedCard()]);
    const first = await app.request("/feed?style=stoic&limit=24");
    expect(first.status).toBe(200);
    expect(listRankedFeed).toHaveBeenCalledWith(expect.objectContaining({ style: "stoic" }));

    const body = (await jsonOf(first)) as { page: { nextCursor: string } };
    const session = decodeFeedSession(body.page.nextCursor);
    expect(session?.offset).toBe(1);

    const second = await app.request(
      `/feed?style=stoic&limit=24&before=${encodeURIComponent(body.page.nextCursor)}`,
    );
    expect(second.status).toBe(200);
    expect(listRankedFeed).toHaveBeenLastCalledWith(
      expect.objectContaining({
        style: "stoic",
        session: expect.objectContaining({ seed: session?.seed, offset: 1 }),
      }),
    );
  });

  it("continues the session the client echoes back", async () => {
    vi.mocked(listRankedFeed).mockResolvedValue([]);
    const session = {
      seed: "seed-abcdefgh",
      startedAt: new Date("2026-09-28T09:00:00.000Z"),
      offset: 24,
    };
    const response = await app.request(
      `/feed?limit=24&before=${encodeURIComponent(encodeFeedSession(session))}`,
    );
    expect(response.status).toBe(200);
    expect(listRankedFeed).toHaveBeenCalledWith(expect.objectContaining({ session }));
  });

  it("keeps arrivals chronological so a new post cannot rank out of sight", async () => {
    vi.mocked(listFeed).mockResolvedValue([]);
    const after = `2026-09-10T12:00:00.000Z|${CARD_ID}`;
    const response = await app.request(`/feed?after=${encodeURIComponent(after)}&limit=8`);
    expect(response.status).toBe(200);
    expect(listRankedFeed).not.toHaveBeenCalled();
    expect(listFeed).toHaveBeenCalledWith(
      expect.objectContaining({
        after: { createdAt: new Date("2026-09-10T12:00:00.000Z"), id: CARD_ID },
      }),
    );
    await expect(jsonOf(response)).resolves.toEqual({ cards: [] });
  });

  it("still accepts a chronological cursor, so a client mid-page is not stranded", async () => {
    vi.mocked(listFeed).mockResolvedValue([]);
    const before = `2026-09-10T12:00:00.000Z|${CARD_ID}`;
    const response = await app.request(`/feed?before=${encodeURIComponent(before)}`);
    expect(response.status).toBe(200);
    expect(listRankedFeed).not.toHaveBeenCalled();
    expect(listFeed).toHaveBeenCalledWith(
      expect.objectContaining({
        before: { createdAt: new Date("2026-09-10T12:00:00.000Z"), id: CARD_ID },
      }),
    );
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
    vi.mocked(clearFeedSaves).mockResolvedValue({ ok: true });
    const response = await app.request(`/feed/cards/${CARD_ID}/saves`, { method: "DELETE" });
    expect(response.status).toBe(204);
  });
});
