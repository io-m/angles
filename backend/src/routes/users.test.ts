import { beforeEach, describe, expect, it, vi } from "vitest";
import { DEV_USER_ID } from "../lib/authStub.js";
import { STYLES, type StoredCard, type StoredCardAuthor } from "../types/index.js";

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

vi.mock("../db/users.js", () => ({
  getUserById: vi.fn(),
  setOwnerAvatar: vi.fn(),
  updateOwnerInitials: vi.fn(),
}));

vi.mock("../db/feed.js", () => ({
  listFeed: vi.fn(),
  listPublicCardsForUser: vi.fn(),
  saveFeedAngle: vi.fn(),
  unsaveFeedAngle: vi.fn(),
  clearFeedSaves: vi.fn(),
}));

const { createApp } = await import("../app.js");
const { listPublicCardsForUser } = await import("../db/feed.js");
const { getUserById } = await import("../db/users.js");

const app = createApp();
const AUTHOR_ID = "00000000-0000-4000-8000-000000000099";
const CARD_ID = "22222222-2222-4222-8222-222222222222";

function author(overrides: Partial<StoredCardAuthor> = {}): StoredCardAuthor {
  return { id: AUTHOR_ID, initials: "AL", ...overrides };
}

function userRow(overrides: { id?: string; initials?: string; avatarKey?: string | null } = {}) {
  return {
    id: overrides.id ?? AUTHOR_ID,
    initials: overrides.initials ?? "AL",
    avatarKey: overrides.avatarKey ?? null,
    createdAt: new Date("2026-09-01T00:00:00.000Z"),
  };
}

function publicCard(overrides: Partial<StoredCard> = {}): StoredCard {
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
    author: author(),
    ...overrides,
  };
}

async function jsonOf(response: Response): Promise<unknown> {
  return response.json();
}

describe("GET /users/:id/cards", () => {
  beforeEach(() => {
    vi.mocked(getUserById).mockReset();
    vi.mocked(listPublicCardsForUser).mockReset();
    vi.mocked(getUserById).mockResolvedValue(userRow());
    vi.mocked(listPublicCardsForUser).mockResolvedValue([]);
  });

  it("returns that author's public cards and initials", async () => {
    const card = publicCard();
    vi.mocked(listPublicCardsForUser).mockResolvedValue([card]);

    const response = await app.request(`/users/${AUTHOR_ID}/cards`);
    expect(response.status).toBe(200);
    await expect(jsonOf(response)).resolves.toEqual({
      user: { id: AUTHOR_ID, initials: "AL" },
      cards: [card],
    });
    expect(listPublicCardsForUser).toHaveBeenCalledWith({
      userId: AUTHOR_ID,
      limit: 24,
      before: undefined,
    });
  });

  it("returns an empty list when the author has no public cards", async () => {
    const response = await app.request(`/users/${AUTHOR_ID}/cards`);
    expect(response.status).toBe(200);
    await expect(jsonOf(response)).resolves.toEqual({
      user: { id: AUTHOR_ID, initials: "AL" },
      cards: [],
    });
    expect(listPublicCardsForUser).toHaveBeenCalledOnce();
  });

  it("builds the avatar path from the photo key and does not add a display name", async () => {
    vi.mocked(getUserById).mockResolvedValue(
      userRow({ avatarKey: `avatars/${AUTHOR_ID}-1700000000000.jpg` }),
    );

    const response = await app.request(`/users/${AUTHOR_ID}/cards`);
    expect(response.status).toBe(200);
    await expect(jsonOf(response)).resolves.toEqual({
      user: {
        id: AUTHOR_ID,
        initials: "AL",
        avatarUrl: `/avatars/${AUTHOR_ID}?v=1700000000000`,
      },
      cards: [],
    });
  });

  it("passes owner hearts and viewer hearts through unchanged", async () => {
    const ownerCard = publicCard({
      id: "33333333-3333-4333-8333-333333333333",
      isOwner: true,
      author: { id: DEV_USER_ID, initials: "JM" },
      results: STYLES.map((style) => ({
        style,
        reframe: `A ${style} take.`,
        isFavorite: style === "stoic",
        ...(style === "stoic" ? { favoritedAt: "2026-09-10T12:00:00.000Z" } : {}),
      })),
    });
    const viewerCard = publicCard({
      isOwner: false,
      results: STYLES.map((style) => ({
        style,
        reframe: `A ${style} take.`,
        isFavorite: style === "optimistic",
        ...(style === "optimistic" ? { favoritedAt: "2026-09-11T12:00:00.000Z" } : {}),
      })),
    });
    vi.mocked(getUserById).mockResolvedValue(userRow({ id: DEV_USER_ID, initials: "JM" }));
    vi.mocked(listPublicCardsForUser).mockResolvedValue([ownerCard, viewerCard]);

    const response = await app.request(`/users/${DEV_USER_ID}/cards?limit=24`);
    expect(response.status).toBe(200);
    await expect(jsonOf(response)).resolves.toEqual({
      user: { id: DEV_USER_ID, initials: "JM" },
      cards: [ownerCard, viewerCard],
    });
    expect(listPublicCardsForUser).toHaveBeenCalledWith({
      userId: DEV_USER_ID,
      limit: 24,
      before: undefined,
    });
  });

  it("decodes the composite keyset cursor", async () => {
    const before = `2026-09-10T12:00:00.000Z|${CARD_ID}`;
    const response = await app.request(`/users/${AUTHOR_ID}/cards?before=${encodeURIComponent(before)}&limit=24`);
    expect(response.status).toBe(200);
    expect(listPublicCardsForUser).toHaveBeenCalledWith({
      userId: AUTHOR_ID,
      limit: 24,
      before: { createdAt: new Date("2026-09-10T12:00:00.000Z"), id: CARD_ID },
    });
  });

  it("404s an unknown user without listing cards", async () => {
    vi.mocked(getUserById).mockResolvedValue(undefined);
    const response = await app.request(`/users/${AUTHOR_ID}/cards`);
    expect(response.status).toBe(404);
    await expect(jsonOf(response)).resolves.toEqual({ error: "Not found", code: "NOT_FOUND" });
    expect(listPublicCardsForUser).not.toHaveBeenCalled();
  });

  it.each([
    "/users/not-a-uuid/cards",
    `/users/${AUTHOR_ID}/cards?categories=work`,
    `/users/${AUTHOR_ID}/cards?emotions=fear`,
    `/users/${AUTHOR_ID}/cards?style=stoic`,
    `/users/${AUTHOR_ID}/cards?before=not-a-cursor`,
  ])("rejects %s", async (path) => {
    const response = await app.request(path);
    expect(response.status).toBe(400);
    await expect(jsonOf(response)).resolves.toMatchObject({ code: "VALIDATION_ERROR" });
    expect(getUserById).not.toHaveBeenCalled();
    expect(listPublicCardsForUser).not.toHaveBeenCalled();
  });
});
