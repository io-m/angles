import { beforeEach, describe, expect, it, vi } from "vitest";
import { DEV_USER_ID } from "../lib/authStub.js";
import { signCook, signResult } from "../lib/cookSignature.js";
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
  hasPublicationReportLock: vi.fn(async () => false),
  patchCard: vi.fn(),
  deleteCard: vi.fn(),
}));

vi.mock("../db/communitySafety.js", () => ({
  reportCard: vi.fn(),
  blockUser: vi.fn(),
  unblockUser: vi.fn(),
  usersAreBlocked: vi.fn(async () => false),
  listBlockedUsers: vi.fn(),
}));

vi.mock("../lib/publicModeration.js", () => ({
  moderatePublicCard: vi.fn(async () => true),
}));

const { createApp } = await import("../app.js");
const { createCard, deleteCard, getCard, hasPublicationReportLock, listCards, patchCard } =
  await import("../db/cards.js");
const { reportCard } = await import("../db/communitySafety.js");
const { moderatePublicCard } = await import("../lib/publicModeration.js");

const app = createApp();
const CARD_ID = "11111111-1111-4111-8111-111111111111";

const cookThought = "I bombed my interview and I keep replaying every shaky answer.";
const cookModel = "mistral-small-latest" as const;
const cookMeta = {
  category: "work" as const,
  tags: ["job_interview", "shame"],
  intensity: 5,
  timeframe: "past" as const,
  emotions: ["shame" as const, "fear" as const],
  safety: "none" as const,
  inputLanguage: "en",
  skippedStyles: [] as [],
};

const cookBody = {
  thought: cookThought,
  results: STYLES.map((style) => ({
    style,
    reframe: `A ${style} take.`,
    signature: signResult(cookThought, style, `A ${style} take.`, cookModel),
  })),
  meta: {
    ...cookMeta,
    matching: { category: "work" as const, tags: ["ignored"], intensityBand: "low" as const },
  },
  signature: signCook({ thought: cookThought, model: cookModel, meta: cookMeta }),
  model: cookModel,
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
    results: cookBody.results.map(({ style, reframe }) => ({ style, reframe, isFavorite: false })),
    model: cookBody.model,
    spotlightStyle: "stoic",
    isPublic: false,
    createdAt: "2026-09-10T12:00:00.000Z",
    isOwner: true,
    author: { id: DEV_USER_ID, initials: "JM", following: false },
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
    vi.mocked(moderatePublicCard).mockReset();
    vi.mocked(moderatePublicCard).mockResolvedValue(true);
  });

  it("creates a card and returns 201", async () => {
    const stored = storedCard();
    vi.mocked(createCard).mockResolvedValue(stored);

    const response = await app.request(jsonRequest("/cards", "POST", cookBody));
    expect(response.status).toBe(201);
    await expect(jsonOf(response)).resolves.toEqual(stored);
    expect(createCard).toHaveBeenCalledTimes(1);
    const payload = vi.mocked(createCard).mock.calls[0]?.[0] as CreateCardInput;
    expect(payload).not.toHaveProperty("signature");
    expect(payload.results[0]).toEqual({ style: "stoic", reframe: "A stoic take." });
  });

  it("rejects a card without signatures", async () => {
    const { signature: _signature, ...unsigned } = cookBody;
    const response = await app.request(
      jsonRequest("/cards", "POST", {
        ...unsigned,
        results: unsigned.results.map(({ style, reframe }) => ({ style, reframe })),
      }),
    );
    expect(response.status).toBe(400);
    await expect(jsonOf(response)).resolves.toMatchObject({ code: "VALIDATION_ERROR" });
    expect(createCard).not.toHaveBeenCalled();
  });

  it.each([
    ["thought", { thought: "Something the server never cooked." }],
    ["model", { model: "deepseek-flash" }],
    ["meta", { meta: { ...cookBody.meta, category: "money" } }],
    ["safety", { meta: { ...cookBody.meta, safety: "self_harm" } }],
    [
      "reframe",
      {
        results: cookBody.results.map((item) =>
          item.style === "stoic" ? { ...item, reframe: "Something else entirely." } : item,
        ),
      },
    ],
  ])("rejects a tampered %s", async (_field, override) => {
    const response = await app.request(jsonRequest("/cards", "POST", { ...cookBody, ...override }));
    expect(response.status).toBe(400);
    await expect(jsonOf(response)).resolves.toMatchObject({ code: "VALIDATION_ERROR" });
    expect(createCard).not.toHaveBeenCalled();
  });

  it("rejects a signed cook that carries a safety flag", async () => {
    const flaggedMeta = { ...cookMeta, safety: "self_harm" as const };
    const response = await app.request(
      jsonRequest("/cards", "POST", {
        ...cookBody,
        meta: flaggedMeta,
        signature: signCook({ thought: cookThought, model: cookModel, meta: flaggedMeta }),
      }),
    );
    expect(response.status).toBe(400);
    expect(createCard).not.toHaveBeenCalled();
  });

  it("accepts a subset of signed results", async () => {
    vi.mocked(createCard).mockResolvedValue(storedCard());
    const response = await app.request(
      jsonRequest("/cards", "POST", { ...cookBody, results: cookBody.results.slice(0, 2) }),
    );
    expect(response.status).toBe(201);
  });

  it("rejects results signed for a different model", async () => {
    const results = cookBody.results.map(({ style, reframe }) => ({
      style,
      reframe,
      signature: signResult(cookThought, style, reframe, "deepseek-flash"),
    }));
    const response = await app.request(
      jsonRequest("/cards", "POST", { ...cookBody, results }),
    );
    expect(response.status).toBe(400);
    await expect(jsonOf(response)).resolves.toMatchObject({ code: "VALIDATION_ERROR" });
    expect(createCard).not.toHaveBeenCalled();
  });

  it("forwards isPublic on create", async () => {
    vi.mocked(createCard).mockResolvedValue(storedCard({ isPublic: true }));

    const response = await app.request(
      jsonRequest("/cards", "POST", { ...cookBody, isPublic: true }),
    );
    expect(response.status).toBe(201);
    const payload = vi.mocked(createCard).mock.calls[0]?.[0] as CreateCardInput;
    expect(payload.isPublic).toBe(true);
    expect(moderatePublicCard).toHaveBeenCalledWith({
      thought: cookThought,
      reframes: cookBody.results.map((result) => result.reframe),
    });
  });

  it("rejects public content disallowed by moderation", async () => {
    vi.mocked(moderatePublicCard).mockResolvedValue(false);
    const response = await app.request(
      jsonRequest("/cards", "POST", { ...cookBody, isPublic: true }),
    );
    expect(response.status).toBe(400);
    await expect(jsonOf(response)).resolves.toMatchObject({ code: "PUBLIC_CONTENT_NOT_ALLOWED" });
    expect(createCard).not.toHaveBeenCalled();
  });

  it("fails public creation closed when moderation is unavailable", async () => {
    vi.mocked(moderatePublicCard).mockRejectedValue(new Error("provider unavailable"));
    const response = await app.request(
      jsonRequest("/cards", "POST", { ...cookBody, isPublic: true }),
    );
    expect(response.status).toBe(503);
    await expect(jsonOf(response)).resolves.toMatchObject({
      code: "PUBLIC_MODERATION_UNAVAILABLE",
    });
    expect(createCard).not.toHaveBeenCalled();
  });

  it("omits isPublic when the client does not send it", async () => {
    vi.mocked(createCard).mockResolvedValue(storedCard());

    const response = await app.request(jsonRequest("/cards", "POST", cookBody));
    expect(response.status).toBe(201);
    const payload = vi.mocked(createCard).mock.calls[0]?.[0] as CreateCardInput;
    expect(payload.isPublic).toBeUndefined();
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
          {
            style: "stoic",
            reframe: "one",
            signature: signResult(cookThought, "stoic", "one", cookModel),
          },
          {
            style: "stoic",
            reframe: "two",
            signature: signResult(cookThought, "stoic", "two", cookModel),
          },
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
    });
  });

  it("passes list filters", async () => {
    vi.mocked(listCards).mockResolvedValue([]);
    const createdAt = "2026-09-10T12:00:00.000Z";
    const response = await app.request(
      `/cards?limit=10&before=${encodeURIComponent(`${createdAt}|${CARD_ID}`)}&category=work&style=stoic&favorite=true`,
    );
    expect(response.status).toBe(200);
    expect(listCards).toHaveBeenCalledWith({
      limit: 10,
      before: { createdAt: new Date(createdAt), id: CARD_ID },
      category: "work",
      style: "stoic",
      favorite: true,
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
    vi.mocked(getCard).mockReset();
    vi.mocked(getCard).mockResolvedValue(storedCard());
    vi.mocked(hasPublicationReportLock).mockReset();
    vi.mocked(hasPublicationReportLock).mockResolvedValue(false);
    vi.mocked(moderatePublicCard).mockReset();
    vi.mocked(moderatePublicCard).mockResolvedValue(true);
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

  it("sets public on its own", async () => {
    const stored = storedCard({ isPublic: true });
    vi.mocked(patchCard).mockResolvedValue({ ok: true, card: stored });

    const response = await app.request(
      jsonRequest(`/cards/${CARD_ID}`, "PATCH", { isPublic: true }),
    );
    expect(response.status).toBe(200);
    expect(patchCard).toHaveBeenCalledWith(CARD_ID, expect.objectContaining({ isPublic: true }));
  });

  it("keeps private patches available when moderation is unavailable", async () => {
    vi.mocked(patchCard).mockResolvedValue({ ok: true, card: storedCard({ isPublic: false }) });
    vi.mocked(moderatePublicCard).mockRejectedValue(new Error("provider unavailable"));
    const response = await app.request(
      jsonRequest(`/cards/${CARD_ID}`, "PATCH", { isPublic: false }),
    );
    expect(response.status).toBe(200);
    expect(moderatePublicCard).not.toHaveBeenCalled();
  });

  it("rejects a public patch disallowed by moderation", async () => {
    vi.mocked(moderatePublicCard).mockResolvedValue(false);
    const response = await app.request(
      jsonRequest(`/cards/${CARD_ID}`, "PATCH", { isPublic: true }),
    );
    expect(response.status).toBe(400);
    await expect(jsonOf(response)).resolves.toMatchObject({ code: "PUBLIC_CONTENT_NOT_ALLOWED" });
    expect(patchCard).not.toHaveBeenCalled();
  });

  it("fails a public patch closed when moderation is unavailable", async () => {
    vi.mocked(moderatePublicCard).mockRejectedValue(new Error("provider unavailable"));
    const response = await app.request(
      jsonRequest(`/cards/${CARD_ID}`, "PATCH", { isPublic: true }),
    );
    expect(response.status).toBe(503);
    await expect(jsonOf(response)).resolves.toMatchObject({
      code: "PUBLIC_MODERATION_UNAVAILABLE",
    });
    expect(patchCard).not.toHaveBeenCalled();
  });

  it("prevents republishing a card locked by reports", async () => {
    vi.mocked(hasPublicationReportLock).mockResolvedValue(true);
    const response = await app.request(
      jsonRequest(`/cards/${CARD_ID}`, "PATCH", { isPublic: true }),
    );
    expect(response.status).toBe(400);
    await expect(jsonOf(response)).resolves.toMatchObject({ code: "PUBLIC_CONTENT_NOT_ALLOWED" });
    expect(moderatePublicCard).not.toHaveBeenCalled();
    expect(patchCard).not.toHaveBeenCalled();
  });

  it("rejects a pin patch now that pins are gone", async () => {
    const response = await app.request(
      jsonRequest(`/cards/${CARD_ID}`, "PATCH", { isPinned: true }),
    );
    expect(response.status).toBe(400);
    await expect(jsonOf(response)).resolves.toMatchObject({ code: "VALIDATION_ERROR" });
    expect(patchCard).not.toHaveBeenCalled();
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
      jsonRequest(`/cards/${CARD_ID}`, "PATCH", { isPublic: true }),
    );
    expect(response.status).toBe(404);
    await expect(jsonOf(response)).resolves.toEqual({ error: "Not found", code: "NOT_FOUND" });
  });
});

describe("POST /cards/:id/report", () => {
  beforeEach(() => {
    vi.mocked(reportCard).mockReset();
  });

  it("reports a public card idempotently", async () => {
    vi.mocked(reportCard).mockResolvedValue({ ok: true, created: false });
    const response = await app.request(
      jsonRequest(`/cards/${CARD_ID}/report`, "POST", { reason: "harassment" }),
    );
    expect(response.status).toBe(200);
    await expect(jsonOf(response)).resolves.toEqual({ reported: true });
    expect(reportCard).toHaveBeenCalledWith(CARD_ID, "harassment");
  });

  it("rejects reporting an own or private card", async () => {
    vi.mocked(reportCard).mockResolvedValue({ ok: false, reason: "own_card" });
    const response = await app.request(
      jsonRequest(`/cards/${CARD_ID}/report`, "POST", { reason: "spam" }),
    );
    expect(response.status).toBe(400);
    await expect(jsonOf(response)).resolves.toMatchObject({ code: "VALIDATION_ERROR" });
  });

  it("rejects an unknown report reason", async () => {
    const response = await app.request(
      jsonRequest(`/cards/${CARD_ID}/report`, "POST", { reason: "dislike" }),
    );
    expect(response.status).toBe(400);
    expect(reportCard).not.toHaveBeenCalled();
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
