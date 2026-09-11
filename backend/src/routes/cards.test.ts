import { beforeEach, describe, expect, it, vi } from "vitest";
import { STYLES, type CreateCardInput, type StoredCard } from "../types/index.js";

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

const { createApp } = await import("../app.js");
const { createCard, deleteCard, getCard, listCards, patchCard } = await import("../db/cards.js");

const app = createApp();
const CARD_ID = "11111111-1111-4111-8111-111111111111";

const cookBody = {
  thought: "I bombed my interview and I keep replaying every shaky answer.",
  results: STYLES.map((style) => ({ style, reframe: `A ${style} take.` })),
  meta: {
    category: "work" as const,
    tags: ["job_interview", "shame"],
    intensity: 5,
    timeframe: "past" as const,
    emotions: ["shame", "fear"],
    safety: "none" as const,
    inputLanguage: "en",
    skippedStyles: [] as [],
    matching: { category: "work" as const, tags: ["ignored"], intensityBand: "low" as const },
  },
  model: "mistral-small-latest" as const,
  spotlightStyle: "stoic" as const,
};

function storedCard(overrides: Partial<StoredCard> = {}): StoredCard {
  return {
    id: CARD_ID,
    thought: cookBody.thought,
    inputLanguage: "en",
    category: "work",
    tags: [
      { slug: "job_interview", label: "Job Interview" },
      { slug: "shame", label: "Shame" },
    ],
    intensity: 5,
    intensityBand: "high",
    timeframe: "past",
    emotions: ["shame", "fear"],
    safety: "none",
    skippedStyles: [],
    matching: { category: "work", tags: ["job_interview", "shame"], intensityBand: "high" },
    results: cookBody.results.map((item) => ({ ...item, isFavorite: false })),
    model: cookBody.model,
    spotlightStyle: "stoic",
    isPinned: false,
    isPublic: false,
    createdAt: "2026-09-10T12:00:00.000Z",
    isOwner: true,
    author: { initials: "JM" },
    ...overrides,
  };
}

async function jsonOf(response: Response): Promise<unknown> {
  return response.json();
}

function jsonRequest(path: string, method: string, body?: unknown): Request {
  return new Request(`http://localhost${path}`, {
    method,
    headers: body === undefined ? undefined : { "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

describe("POST /cards", () => {
  beforeEach(() => {
    vi.mocked(createCard).mockReset();
  });

  it("creates a card and returns 201", async () => {
    const stored = storedCard();
    vi.mocked(createCard).mockResolvedValue(stored);

    const response = await app.request(jsonRequest("/cards", "POST", cookBody));
    expect(response.status).toBe(201);
    await expect(jsonOf(response)).resolves.toEqual(stored);
    expect(createCard).toHaveBeenCalledTimes(1);
  });

  it("strips client matching before the db seam", async () => {
    vi.mocked(createCard).mockResolvedValue(storedCard());

    const response = await app.request(jsonRequest("/cards", "POST", cookBody));
    expect(response.status).toBe(201);

    const payload = vi.mocked(createCard).mock.calls[0]?.[0] as CreateCardInput;
    expect(payload.meta).not.toHaveProperty("matching");
    expect(payload.meta.intensity).toBe(5);
  });

  it("rejects an empty thought", async () => {
    const response = await app.request(
      jsonRequest("/cards", "POST", { ...cookBody, thought: "  " }),
    );
    expect(response.status).toBe(400);
    await expect(jsonOf(response)).resolves.toMatchObject({ code: "VALIDATION_ERROR" });
    expect(createCard).not.toHaveBeenCalled();
  });

  it("rejects duplicate result styles", async () => {
    const response = await app.request(
      jsonRequest("/cards", "POST", {
        ...cookBody,
        results: [
          { style: "stoic", reframe: "one" },
          { style: "stoic", reframe: "two" },
        ],
      }),
    );
    expect(response.status).toBe(400);
    await expect(jsonOf(response)).resolves.toMatchObject({ code: "VALIDATION_ERROR" });
    expect(createCard).not.toHaveBeenCalled();
  });
});

describe("GET /cards", () => {
  beforeEach(() => {
    vi.mocked(listCards).mockReset();
  });

  it("lists cards newest first via the db seam", async () => {
    const stored = storedCard();
    vi.mocked(listCards).mockResolvedValue([stored]);

    const response = await app.request("/cards");
    expect(response.status).toBe(200);
    await expect(jsonOf(response)).resolves.toEqual({ cards: [stored] });
    expect(listCards).toHaveBeenCalledWith({
      limit: 50,
      before: undefined,
      category: undefined,
      style: undefined,
      favorite: undefined,
      pinned: undefined,
    });
  });

  it("passes list filters", async () => {
    vi.mocked(listCards).mockResolvedValue([]);
    const before = "2026-09-10T12:00:00.000Z";
    const response = await app.request(
      `/cards?limit=10&before=${encodeURIComponent(before)}&category=work&style=stoic&favorite=true&pinned=true`,
    );
    expect(response.status).toBe(200);
    expect(listCards).toHaveBeenCalledWith({
      limit: 10,
      before: new Date(before),
      category: "work",
      style: "stoic",
      favorite: true,
      pinned: true,
    });
  });
});

describe("GET /cards/:id", () => {
  beforeEach(() => {
    vi.mocked(getCard).mockReset();
  });

  it("returns a stored card", async () => {
    const stored = storedCard();
    vi.mocked(getCard).mockResolvedValue(stored);
    const response = await app.request(`/cards/${CARD_ID}`);
    expect(response.status).toBe(200);
    await expect(jsonOf(response)).resolves.toEqual(stored);
  });

  it("returns 404 when missing", async () => {
    vi.mocked(getCard).mockResolvedValue(null);
    const response = await app.request(`/cards/${CARD_ID}`);
    expect(response.status).toBe(404);
    await expect(jsonOf(response)).resolves.toEqual({ error: "Not found", code: "NOT_FOUND" });
  });
});

describe("PATCH /cards/:id", () => {
  beforeEach(() => {
    vi.mocked(patchCard).mockReset();
  });

  it("sets a per-style favorite", async () => {
    const stored = storedCard({
      results: storedCard().results.map((item) =>
        item.style === "stoic"
          ? { ...item, isFavorite: true, favoritedAt: "2026-09-10T12:01:00.000Z" }
          : item,
      ),
    });
    vi.mocked(patchCard).mockResolvedValue({ ok: true, card: stored });

    const response = await app.request(
      jsonRequest(`/cards/${CARD_ID}`, "PATCH", { isFavorite: true, style: "stoic" }),
    );
    expect(response.status).toBe(200);
    await expect(jsonOf(response)).resolves.toEqual(stored);
    expect(patchCard).toHaveBeenCalledWith(
      CARD_ID,
      expect.objectContaining({ isFavorite: true, style: "stoic" }),
    );
  });

  it("sets pin and public independently", async () => {
    const stored = storedCard({
      isPinned: true,
      pinnedAt: "2026-09-10T12:02:00.000Z",
      isPublic: true,
    });
    vi.mocked(patchCard).mockResolvedValue({ ok: true, card: stored });

    const response = await app.request(
      jsonRequest(`/cards/${CARD_ID}`, "PATCH", { isPinned: true, isPublic: true }),
    );
    expect(response.status).toBe(200);
    expect(patchCard).toHaveBeenCalledWith(
      CARD_ID,
      expect.objectContaining({ isPinned: true, isPublic: true }),
    );
  });

  it("rejects favorite without a style", async () => {
    const response = await app.request(
      jsonRequest(`/cards/${CARD_ID}`, "PATCH", { isFavorite: true }),
    );
    expect(response.status).toBe(400);
    await expect(jsonOf(response)).resolves.toMatchObject({ code: "VALIDATION_ERROR" });
    expect(patchCard).not.toHaveBeenCalled();
  });

  it("rejects an empty patch", async () => {
    const response = await app.request(jsonRequest(`/cards/${CARD_ID}`, "PATCH", {}));
    expect(response.status).toBe(400);
    await expect(jsonOf(response)).resolves.toMatchObject({ code: "VALIDATION_ERROR" });
    expect(patchCard).not.toHaveBeenCalled();
  });

  it("returns 400 when the style is not on the card", async () => {
    vi.mocked(patchCard).mockResolvedValue({ ok: false, reason: "unknown_style" });
    const response = await app.request(
      jsonRequest(`/cards/${CARD_ID}`, "PATCH", { isFavorite: true, style: "humorous" }),
    );
    expect(response.status).toBe(400);
    await expect(jsonOf(response)).resolves.toMatchObject({ code: "VALIDATION_ERROR" });
  });

  it("returns 404 when missing", async () => {
    vi.mocked(patchCard).mockResolvedValue({ ok: false, reason: "not_found" });
    const response = await app.request(
      jsonRequest(`/cards/${CARD_ID}`, "PATCH", { isPinned: true }),
    );
    expect(response.status).toBe(404);
    await expect(jsonOf(response)).resolves.toEqual({ error: "Not found", code: "NOT_FOUND" });
  });
});

describe("DELETE /cards/:id", () => {
  beforeEach(() => {
    vi.mocked(deleteCard).mockReset();
  });

  it("hard-deletes and returns 204", async () => {
    vi.mocked(deleteCard).mockResolvedValue(true);
    const response = await app.request(`/cards/${CARD_ID}`, { method: "DELETE" });
    expect(response.status).toBe(204);
    expect(deleteCard).toHaveBeenCalledWith(CARD_ID);
  });

  it("returns 404 when missing", async () => {
    vi.mocked(deleteCard).mockResolvedValue(false);
    const response = await app.request(`/cards/${CARD_ID}`, { method: "DELETE" });
    expect(response.status).toBe(404);
    await expect(jsonOf(response)).resolves.toEqual({ error: "Not found", code: "NOT_FOUND" });
  });
});
