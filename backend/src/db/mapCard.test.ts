import { beforeEach, describe, expect, it, vi } from "vitest";

const followedAuthorIds = vi.fn();
const loadStyleHeartCounts = vi.fn();
const loadViewerStyleTaste = vi.fn();

vi.mock("./follows.js", () => ({
  followedAuthorIds: (...args: unknown[]) => followedAuthorIds(...args),
}));

vi.mock("./hearts.js", () => ({
  loadStyleHeartCounts: (...args: unknown[]) => loadStyleHeartCounts(...args),
  loadViewerStyleTaste: (...args: unknown[]) => loadViewerStyleTaste(...args),
}));

vi.mock("./client.js", () => ({
  getDb: vi.fn(),
  wrapDbError: vi.fn(),
}));

vi.mock("../lib/authStub.js", () => ({
  getOwnerUserId: () => "00000000-0000-4000-8000-000000000001",
}));

vi.mock("../lib/avatarUrl.js", () => ({
  avatarUrlFor: () => undefined,
}));

vi.mock("../lib/feedRanking.js", () => ({
  openingStyle: () => "stoic",
}));

const { storedCardsForViewer } = await import("./mapCard.js");

describe("storedCardsForViewer", () => {
  beforeEach(() => {
    followedAuthorIds.mockReset();
    loadStyleHeartCounts.mockReset();
    loadViewerStyleTaste.mockReset();
    followedAuthorIds.mockResolvedValue(new Set());
    loadStyleHeartCounts.mockResolvedValue(new Map());
    loadViewerStyleTaste.mockResolvedValue(null);
  });

  it("skips the follow query when ranking already loaded follows", async () => {
    await storedCardsForViewer([], "00000000-0000-4000-8000-000000000001", undefined, {
      followed: new Set(["00000000-0000-4000-8000-000000000099"]),
    });
    expect(followedAuthorIds).not.toHaveBeenCalled();
  });

  it("loads mapping reads together instead of one after another", async () => {
    let inFlight = 0;
    let maxInFlight = 0;
    const track = async <T>(value: T): Promise<T> => {
      inFlight += 1;
      maxInFlight = Math.max(maxInFlight, inFlight);
      await new Promise((resolve) => setTimeout(resolve, 20));
      inFlight -= 1;
      return value;
    };
    followedAuthorIds.mockImplementation(async () => track(new Set()));
    loadStyleHeartCounts.mockImplementation(async () => track(new Map()));
    loadViewerStyleTaste.mockImplementation(async () => track(null));

    const row = {
      id: "22222222-2222-4222-8222-222222222222",
      userId: "00000000-0000-4000-8000-000000000099",
      thoughtEn: "I keep waiting for a reply.",
      thoughtOriginal: null,
      inputLanguage: "en",
      category: "work",
      proposedCategory: null,
      proposedLabel: null,
      intensity: 3,
      timeframe: "ongoing",
      emotions: [],
      safety: "none",
      skippedStyles: [],
      model: "mistral-small-latest",
      spotlightStyle: "stoic",
      isPublic: true,
      createdAt: new Date("2026-10-08T10:00:00.000Z"),
      moderationHiddenAt: null,
      reframes: [
        {
          style: "stoic",
          reframe: "Wait without shrinking.",
          reframeOriginal: null,
          isFavorite: false,
          favoritedAt: null,
          position: 0,
        },
      ],
      cardTags: [],
      user: { initials: "AL", avatarKey: null },
    };

    const db = {
      select: () => ({
        from: () => ({
          where: async () => [],
        }),
      }),
    };

    await storedCardsForViewer(
      [row as never],
      "00000000-0000-4000-8000-000000000001",
      db as never,
    );

    expect(followedAuthorIds).toHaveBeenCalled();
    expect(loadStyleHeartCounts).toHaveBeenCalled();
    expect(loadViewerStyleTaste).toHaveBeenCalled();
    expect(maxInFlight).toBeGreaterThan(1);
  });
});
