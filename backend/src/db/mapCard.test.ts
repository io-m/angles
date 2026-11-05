import { beforeEach, describe, expect, it, vi } from "vitest";
import type { CardDecisionRow } from "./schema.js";

const VIEWER_ID = "00000000-0000-4000-8000-000000000001";
const AUTHOR_ID = "00000000-0000-4000-8000-000000000099";
const CARD_ID = "22222222-2222-4222-8222-222222222222";

const followedAuthorIds = vi.fn();
const loadSaveCountsByStyle = vi.fn();
const loadViewerSavedStyle = vi.fn();
const loadViewerDecisions = vi.fn();

vi.mock("./follows.js", () => ({
  followedAuthorIds: (...args: unknown[]) => followedAuthorIds(...args),
}));

vi.mock("./saves.js", () => ({
  loadSaveCountsByStyle: (...args: unknown[]) => loadSaveCountsByStyle(...args),
  loadViewerSavedStyle: (...args: unknown[]) => loadViewerSavedStyle(...args),
}));

vi.mock("./decisions.js", async () => {
  const actual = await vi.importActual<typeof import("./decisions.js")>("./decisions.js");
  return {
    toCardDecision: actual.toCardDecision,
    loadViewerDecisions: (...args: unknown[]) => loadViewerDecisions(...args),
  };
});

vi.mock("./client.js", () => ({
  getDb: vi.fn(),
  wrapDbError: vi.fn(),
  DbError: class DbError extends Error {},
}));

vi.mock("../lib/authStub.js", () => ({
  getOwnerUserId: () => VIEWER_ID,
}));

vi.mock("../lib/avatarUrl.js", () => ({
  avatarUrlFor: () => undefined,
}));

const { storedCardsForViewer } = await import("./mapCard.js");

function cardRow(overrides: Record<string, unknown> = {}) {
  return {
    id: CARD_ID,
    userId: AUTHOR_ID,
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
    reframes: (["stoic", "hopeful", "witty", "tender"] as const).map((style, position) => ({
      style,
      reframe: `A ${style} take.`,
      reframeOriginal: style === "stoic" ? "Una toma." : null,
      position,
    })),
    cardTags: [],
    user: { initials: "AL", avatarKey: null, kind: "person" },
    ...overrides,
  };
}

function decisionRow(overrides: Partial<CardDecisionRow> = {}): CardDecisionRow {
  return {
    userId: VIEWER_ID,
    cardId: CARD_ID,
    kind: "pass",
    style: "stoic",
    checkedStyles: ["stoic"],
    passes: 1,
    decidedAt: new Date("2026-10-08T11:00:00.000Z"),
    ...overrides,
  };
}

describe("storedCardsForViewer", () => {
  beforeEach(() => {
    followedAuthorIds.mockReset().mockResolvedValue(new Set());
    loadSaveCountsByStyle.mockReset().mockResolvedValue(new Map());
    loadViewerSavedStyle.mockReset().mockResolvedValue(null);
    loadViewerDecisions.mockReset().mockResolvedValue(new Map());
  });

  it("skips the follow and taste queries when the stack already read them", async () => {
    await storedCardsForViewer([cardRow() as never], VIEWER_ID, undefined, {
      followed: new Set([AUTHOR_ID]),
      preferredStyle: null,
    });
    expect(followedAuthorIds).not.toHaveBeenCalled();
    expect(loadViewerSavedStyle).not.toHaveBeenCalled();
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
    loadSaveCountsByStyle.mockImplementation(async () => track(new Map()));
    loadViewerSavedStyle.mockImplementation(async () => track(null));
    loadViewerDecisions.mockImplementation(async () => track(new Map()));

    await storedCardsForViewer([cardRow() as never], VIEWER_ID);
    expect(maxInFlight).toBeGreaterThan(1);
  });

  it("opens a returning card on the first angle the viewer has not seen", async () => {
    loadViewerDecisions.mockResolvedValue(
      new Map([[CARD_ID, decisionRow({ checkedStyles: ["stoic", "hopeful"] })]]),
    );
    const [card] = await storedCardsForViewer([cardRow() as never], VIEWER_ID);
    expect(card?.openingStyle).toBe("witty");
    expect(card?.decision).toMatchObject({ kind: "pass", passes: 1, checkedStyles: ["stoic", "hopeful"] });
  });

  it("opens a saved card on the angle it was saved on", async () => {
    loadViewerDecisions.mockResolvedValue(
      new Map([[CARD_ID, decisionRow({ kind: "save", style: "tender", passes: 0 })]]),
    );
    const [card] = await storedCardsForViewer([cardRow() as never], VIEWER_ID);
    expect(card?.openingStyle).toBe("tender");
  });

  it("marks a house card and never shows it as followed", async () => {
    const [card] = await storedCardsForViewer(
      [cardRow({ user: { initials: "A", avatarKey: null, kind: "house" } }) as never],
      VIEWER_ID,
      undefined,
      { followed: new Set([AUTHOR_ID]), preferredStyle: null },
    );
    expect(card?.isHouse).toBe(true);
    expect(card?.author.following).toBe(false);
  });

  it("shows save counts and the original language to the author only", async () => {
    loadSaveCountsByStyle.mockResolvedValue(new Map([[CARD_ID, new Map([["stoic", 2], ["witty", 1]])]]));
    const [own] = await storedCardsForViewer(
      [cardRow({ userId: VIEWER_ID }) as never],
      VIEWER_ID,
    );
    expect(own?.saveCount).toBe(3);
    expect(own?.results.find((item) => item.style === "stoic")).toMatchObject({
      saveCount: 2,
      reframeOriginal: "Una toma.",
    });
    expect(own?.results.find((item) => item.style === "hopeful")?.saveCount).toBeUndefined();
    expect(own?.decision).toBeUndefined();

    const [theirs] = await storedCardsForViewer([cardRow() as never], VIEWER_ID);
    expect(theirs?.saveCount).toBeUndefined();
    expect(theirs?.results.every((item) => item.saveCount === undefined)).toBe(true);
    expect(theirs?.results.every((item) => item.reframeOriginal === undefined)).toBe(true);
  });

  it("never asks for save counts on someone else's or a private card", async () => {
    await storedCardsForViewer(
      [cardRow() as never, cardRow({ id: "33333333-3333-4333-8333-333333333333", userId: VIEWER_ID, isPublic: false }) as never],
      VIEWER_ID,
    );
    expect(loadSaveCountsByStyle).toHaveBeenCalledWith([], undefined);
  });
});
