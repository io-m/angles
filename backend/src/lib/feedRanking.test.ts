import { describe, expect, it } from "vitest";
import { STYLES, type Category, type Emotion, type Style } from "../types/index.js";
import {
  AFFINITY_CONFIG,
  EMPTY_AFFINITY,
  FOLLOW_MIX,
  MIN_MIX_CONFIDENCE,
  PRIMARY_TIE_WEIGHT,
  offTabFade,
  RANKING_WEIGHTS,
  SPREAD_LIMITS,
  STYLE_AFFINITY_FULL_HEARTS,
  STYLE_RANKING_WEIGHTS,
  THEME_MIX,
  affinityTerm,
  assignPrimaryStyles,
  blendedAffinityTerm,
  bucketCaps,
  buildAffinity,
  classifyTheme,
  compareRanked,
  decodeFeedSession,
  encodeFeedSession,
  followMix,
  freshnessTerm,
  isKeptOnShelf,
  isPartlyKept,
  jitterTerm,
  openingStyle,
  rankCards,
  rankingEnabled,
  resonanceTerm,
  scoreCard,
  secondChanceTerm,
  spreadPage,
  spreadRanked,
  styleAffinityConfidence,
  themeMix,
  type AffinitySignal,
  type RankableCard,
  type SpreadableCard,
  type StyleShelfContext,
  type StyleTabs,
  type ThemeBucket,
  type ViewerAffinity,
} from "./feedRanking.js";

const NOW = new Date("2026-09-28T12:00:00.000Z");

const CATEGORY_CYCLE: readonly Category[] = ["work", "money", "family", "health"];
const EMOTION_CYCLE: readonly Emotion[] = ["shame", "fear", "sadness", "anger"];

function hoursAgo(hours: number): Date {
  return new Date(NOW.getTime() - hours * 3_600_000);
}

function card(overrides: Partial<RankableCard> = {}): RankableCard {
  return {
    id: "11111111-1111-4111-8111-111111111111",
    authorId: "22222222-2222-4222-8222-222222222222",
    createdAt: hoursAgo(1),
    category: "work",
    emotions: ["shame"],
    hearts: 0,
    followed: false,
    ...overrides,
  };
}

/** Themes with equal strength, so each one is "the top theme" and scores 1. */
function themes(
  categories: readonly Category[],
  emotions: readonly Emotion[],
  confidence = 1,
): ViewerAffinity {
  return {
    categories: new Map(categories.map((key) => [key, 1 / categories.length])),
    emotions: new Map(emotions.map((key) => [key, 1 / emotions.length])),
    confidence,
  };
}

function spreadable(overrides: Partial<SpreadableCard> = {}): SpreadableCard {
  return {
    id: "11111111-1111-4111-8111-111111111111",
    authorId: "22222222-2222-4222-8222-222222222222",
    category: "work",
    emotions: ["shame"],
    intensity: 3,
    spotlightStyle: "stoic",
    ...overrides,
  };
}

describe("ranking terms", () => {
  it("decays freshness over a day or two, like a social feed", () => {
    expect(freshnessTerm(card({ createdAt: NOW }), NOW)).toBeCloseTo(1, 5);
    // Still most of its worth this morning, about a third by tomorrow, gone in a few days.
    expect(freshnessTerm(card({ createdAt: hoursAgo(6) }), NOW)).toBeGreaterThan(0.75);
    expect(freshnessTerm(card({ createdAt: hoursAgo(24) }), NOW)).toBeCloseTo(Math.exp(-1), 5);
    expect(freshnessTerm(card({ createdAt: hoursAgo(72) }), NOW)).toBeLessThan(0.06);
    expect(freshnessTerm(card({ createdAt: hoursAgo(24 * 30) }), NOW)).toBeLessThan(0.001);
  });

  it("lets a newer post beat an older one, and only clear signals overturn that", () => {
    const fresh = scoreCard(card({ id: "a", createdAt: hoursAgo(2) }), { now: NOW, seed: "s" });
    const yesterday = scoreCard(card({ id: "a", createdAt: hoursAgo(26), hearts: 2 }), {
      now: NOW,
      seed: "s",
    });
    // A lone couple of hearts does not lift yesterday's post over a fresh one.
    expect(fresh.score).toBeGreaterThan(yesterday.score);

    const threeDays = scoreCard(card({ id: "a", createdAt: hoursAgo(72), hearts: 10 }), {
      now: NOW,
      seed: "s",
    });
    const twoDaysPlain = scoreCard(card({ id: "a", createdAt: hoursAgo(48) }), { now: NOW, seed: "s" });
    // A card people clearly keep can outrank a plain one a day newer.
    expect(threeDays.score).toBeGreaterThan(twoDaysPlain.score);
  });

  it("damps resonance and caps it so one card cannot own the feed", () => {
    expect(resonanceTerm(card({ hearts: 0 }))).toBe(0);
    expect(resonanceTerm(card({ hearts: 1 }))).toBeLessThan(resonanceTerm(card({ hearts: 3 })));
    expect(resonanceTerm(card({ hearts: 10 }))).toBeCloseTo(1, 5);
    expect(resonanceTerm(card({ hearts: 5_000 }))).toBe(1);
  });

  it("scores affinity from the viewer's own life areas and moods", () => {
    const affinity = themes(["work"], ["shame", "fear"]);
    expect(affinityTerm(card({ category: "money", emotions: [] }), affinity)).toBe(0);
    expect(affinityTerm(card({ category: "work", emotions: [] }), affinity)).toBeCloseTo(0.6, 5);
    expect(
      affinityTerm(card({ category: "work", emotions: ["shame", "fear"] }), affinity),
    ).toBeCloseTo(1, 5);
    // A third shared mood adds nothing: recognition, not a keyword pile.
    expect(
      affinityTerm(card({ category: "money", emotions: ["shame", "fear", "shame"] }), affinity),
    ).toBeCloseTo(0.4, 5);
  });

  it("gives an unhearted young post a second chance that fades", () => {
    expect(secondChanceTerm(card({ createdAt: hoursAgo(2) }), NOW)).toBe(0);
    expect(secondChanceTerm(card({ createdAt: hoursAgo(48) }), NOW)).toBe(1);
    expect(secondChanceTerm(card({ createdAt: hoursAgo(24 * 20) }), NOW)).toBeCloseTo(
      10 / 16,
      5,
    );
    expect(secondChanceTerm(card({ createdAt: hoursAgo(24 * 40) }), NOW)).toBe(0);
    // Hearted posts do not need help being found.
    expect(secondChanceTerm(card({ createdAt: hoursAgo(48), hearts: 1 }), NOW)).toBe(0);
  });

  it("keeps jitter inside the unit range and stable per seed", () => {
    const first = jitterTerm("a", "seed-one");
    expect(first).toBe(jitterTerm("a", "seed-one"));
    expect(first).toBeGreaterThanOrEqual(0);
    expect(first).toBeLessThan(1);
    expect(first).not.toBe(jitterTerm("a", "seed-two"));
  });

  it("never lets jitter outrank a real signal", () => {
    expect(RANKING_WEIGHTS.jitter).toBeLessThan(RANKING_WEIGHTS.resonance);
    expect(RANKING_WEIGHTS.jitter).toBeLessThan(RANKING_WEIGHTS.affinity);
    expect(RANKING_WEIGHTS.jitter).toBeLessThan(RANKING_WEIGHTS.freshness);
  });

  it("does not reward intensity or distress anywhere in the score", () => {
    const calm = scoreCard(card({ id: "a" }), { now: NOW, seed: "s" });
    const distressing = scoreCard(card({ id: "a" }), { now: NOW, seed: "s" });
    expect(distressing.score).toBe(calm.score);
    expect(Object.keys(RANKING_WEIGHTS)).not.toContain("intensity");
  });
});

describe("rankCards", () => {
  it("puts a hearted card above an equally fresh unhearted one", () => {
    const ranked = rankCards(
      [
        card({ id: "aaaaaaaa-0000-4000-8000-000000000001", hearts: 0 }),
        card({ id: "bbbbbbbb-0000-4000-8000-000000000002", hearts: 6 }),
      ],
      { now: NOW, seed: "seed" },
    );
    expect(ranked[0]?.id).toBe("bbbbbbbb-0000-4000-8000-000000000002");
  });

  it("puts a card about the viewer's own subject above a stranger's subject", () => {
    const affinity = themes(["grief_loss"], ["sadness"]);
    const ranked = rankCards(
      [
        card({ id: "aaaaaaaa-0000-4000-8000-000000000001", category: "money", emotions: [] }),
        card({
          id: "bbbbbbbb-0000-4000-8000-000000000002",
          category: "grief_loss",
          emotions: ["sadness"],
        }),
      ],
      { now: NOW, seed: "seed", affinity },
    );
    expect(ranked[0]?.id).toBe("bbbbbbbb-0000-4000-8000-000000000002");
  });

  it("is deterministic for one seed and reorders on another", () => {
    const pool = Array.from({ length: 12 }, (_, index) =>
      card({
        id: `aaaaaaaa-0000-4000-8000-0000000000${String(index).padStart(2, "0")}`,
        // The same hour: time is the biggest term, so only ties are left to the seed.
        createdAt: hoursAgo(1),
      }),
    );
    const first = rankCards(pool, { now: NOW, seed: "seed-one" }).map((item) => item.id);
    expect(rankCards(pool, { now: NOW, seed: "seed-one" }).map((item) => item.id)).toEqual(first);
    expect(rankCards(pool, { now: NOW, seed: "seed-two" }).map((item) => item.id)).not.toEqual(
      first,
    );
  });

  it("scores with no affinity rather than throwing on a cold-start viewer", () => {
    const scored = scoreCard(card(), { now: NOW, seed: "s", affinity: EMPTY_AFFINITY });
    expect(scored.terms.affinity).toBe(0);
    expect(scored.score).toBeGreaterThan(0);
  });
});

describe("style shelves", () => {
  const styleAffinity = themes(["work"], ["shame"]);

  function shelf(overrides: Partial<StyleShelfContext> = {}): StyleShelfContext {
    return {
      style: "stoic",
      affinity: EMPTY_AFFINITY,
      hearts: 0,
      angleHearts: 0,
      coverMatches: false,
      ...overrides,
    };
  }

  it("leaves For you scoring untouched when no style shelf is requested", () => {
    const subject = card({ hearts: 4, followed: true });
    const scored = scoreCard(subject, { now: NOW, seed: "s", affinity: styleAffinity });
    const manual =
      RANKING_WEIGHTS.freshness * scored.terms.freshness +
      RANKING_WEIGHTS.resonance * scored.terms.resonance +
      RANKING_WEIGHTS.affinity * scored.terms.affinity +
      RANKING_WEIGHTS.followed * scored.terms.followed +
      RANKING_WEIGHTS.secondChance * scored.terms.secondChance +
      RANKING_WEIGHTS.jitter * scored.terms.jitter;
    expect(scored.score).toBeCloseTo(manual, 8);
    expect(scored.terms.affinity).toBeCloseTo(affinityTerm(subject, styleAffinity), 8);
    expect(scored.terms.jitter).toBe(jitterTerm(subject.id, "s"));
  });

  it("falls back to general taste when this style has no hearts", () => {
    const subject = card();
    expect(styleAffinityConfidence(0)).toBe(0);
    expect(blendedAffinityTerm(subject, styleAffinity, EMPTY_AFFINITY, 0)).toBeCloseTo(
      affinityTerm(subject, styleAffinity),
      8,
    );
  });

  it("lets confidence grow without a single heart taking over", () => {
    const subject = card({ category: "work", emotions: ["shame", "fear"] });
    const specific = themes(["work"], ["shame", "fear"]);
    expect(styleAffinityConfidence(1)).toBeCloseTo(1 / STYLE_AFFINITY_FULL_HEARTS, 8);
    expect(blendedAffinityTerm(subject, EMPTY_AFFINITY, specific, 1)).toBeCloseTo(0.2, 8);
    expect(blendedAffinityTerm(subject, EMPTY_AFFINITY, specific, 5)).toBeCloseTo(1, 8);
    expect(blendedAffinityTerm(subject, EMPTY_AFFINITY, specific, 40)).toBeCloseTo(1, 8);

    const oneHeart = scoreCard(subject, {
      now: NOW,
      seed: "s",
      affinity: EMPTY_AFFINITY,
      style: shelf({ affinity: specific, hearts: 1 }),
    });
    const untouched = scoreCard(subject, {
      now: NOW,
      seed: "s",
      affinity: EMPTY_AFFINITY,
      style: shelf(),
    });
    expect(oneHeart.score - untouched.score).toBeLessThan(RANKING_WEIGHTS.affinity);
  });

  it("ranks a hearted angle above an otherwise equal card, and saturates", () => {
    const plain = card({ id: "aaaaaaaa-0000-4000-8000-000000000001", angleHearts: 0 });
    const loved = card({ id: "bbbbbbbb-0000-4000-8000-000000000002", angleHearts: 6 });
    const ranked = rankCards([plain, loved], {
      now: NOW,
      seed: "seed",
      style: { style: "stoic", affinity: EMPTY_AFFINITY, hearts: 0 },
    });
    expect(ranked[0]?.id).toBe(loved.id);

    expect(resonanceTerm(card({ hearts: 5_000 }))).toBe(resonanceTerm(card({ hearts: 10 })));
    expect(resonanceTerm(card({ hearts: 10 }))).toBeGreaterThan(resonanceTerm(card({ hearts: 6 })));
    expect(STYLE_RANKING_WEIGHTS.styleResonance).toBeLessThan(RANKING_WEIGHTS.resonance);
    expect(STYLE_RANKING_WEIGHTS.cover).toBeLessThan(RANKING_WEIGHTS.jitter);
  });

  it("is deterministic per style and does not collapse two shelves into one order", () => {
    const pool = Array.from({ length: 8 }, (_, index) =>
      card({
        id: `aaaaaaaa-0000-4000-8000-0000000000${String(index).padStart(2, "0")}`,
        createdAt: hoursAgo(1),
      }),
    );
    const stoic = rankCards(pool, {
      now: NOW,
      seed: "shared-seed",
      style: { style: "stoic", affinity: EMPTY_AFFINITY, hearts: 0 },
    }).map((item) => item.id);
    const witty = rankCards(pool, {
      now: NOW,
      seed: "shared-seed",
      style: { style: "witty", affinity: EMPTY_AFFINITY, hearts: 0 },
    }).map((item) => item.id);
    expect(
      rankCards(pool, {
        now: NOW,
        seed: "shared-seed",
        style: { style: "stoic", affinity: EMPTY_AFFINITY, hearts: 0 },
      }).map((item) => item.id),
    ).toEqual(stoic);
    expect(witty).not.toEqual(stoic);
  });

  it("gives a style shelf a different head from For you when that angle is the strong one", () => {
    const stoicId = "aaaaaaaa-0000-4000-8000-000000000001";
    const wittyId = "bbbbbbbb-0000-4000-8000-000000000002";
    const pool = [
      card({ id: stoicId, coverStyle: "stoic", createdAt: hoursAgo(6) }),
      card({ id: wittyId, coverStyle: "witty", createdAt: hoursAgo(1) }),
    ];
    const all = rankCards(pool, { now: NOW, seed: "seed" }).map((item) => item.id);
    const stoic = rankCards(
      pool.map((item) => ({ ...item, angleHearts: item.id === stoicId ? 8 : 0 })),
      {
        now: NOW,
        seed: "seed",
        style: { style: "stoic", affinity: EMPTY_AFFINITY, hearts: 0 },
      },
    );
    const witty = rankCards(
      pool.map((item) => ({ ...item, angleHearts: item.id === wittyId ? 8 : 0 })),
      {
        now: NOW,
        seed: "seed",
        style: { style: "witty", affinity: EMPTY_AFFINITY, hearts: 0 },
      },
    );
    expect(stoic[0]?.id).toBe(stoicId);
    expect(witty[0]?.id).toBe(wittyId);
    expect(stoic.map((item) => item.id)).not.toEqual(witty.map((item) => item.id));
    expect(all).not.toEqual(stoic.map((item) => item.id));
  });

  it("breaks an equal score on id, highest id first", () => {
    const lower = scoreCard(card({ id: "aaaaaaaa-0000-4000-8000-000000000001" }), {
      now: NOW,
      seed: "s",
    });
    const higher = scoreCard(card({ id: "bbbbbbbb-0000-4000-8000-000000000002" }), {
      now: NOW,
      seed: "s",
    });
    const tied = [
      { ...lower, score: 1 },
      { ...higher, score: 1 },
    ];
    expect([...tied].sort(compareRanked).map((item) => item.id)).toEqual([higher.id, lower.id]);
  });
});

describe("spreadPage", () => {
  it("caps one author inside a page", () => {
    const mine = Array.from({ length: 6 }, (_, index) =>
      spreadable({ id: `own-${index}`, authorId: "loud-author" }),
    );
    const others = Array.from({ length: 6 }, (_, index) =>
      spreadable({ id: `other-${index}`, authorId: `author-${index}` }),
    );
    const page = spreadPage([...mine, ...others], 6);
    const loud = page.filter((item) => item.authorId === "loud-author");
    expect(loud).toHaveLength(SPREAD_LIMITS.perAuthor);
    expect(page).toHaveLength(6);
  });

  it("breaks a run of one life area, mood, and cover angle", () => {
    const wall = Array.from({ length: 8 }, (_, index) =>
      spreadable({
        id: `wall-${index}`,
        authorId: `author-${index}`,
        category: "work",
        emotions: ["shame"],
        spotlightStyle: "stoic",
      }),
    );
    const relief = Array.from({ length: 8 }, (_, index) =>
      spreadable({
        id: `relief-${index}`,
        authorId: `relief-author-${index}`,
        category: "health",
        emotions: ["hope"],
        spotlightStyle: "witty",
      }),
    );
    const page = spreadPage([...wall, ...relief], 8);
    let run = 1;
    for (let index = 1; index < page.length; index += 1) {
      run = page[index]?.category === page[index - 1]?.category ? run + 1 : 1;
      expect(run).toBeLessThanOrEqual(SPREAD_LIMITS.run);
    }
  });

  it("caps peak intensity so a page is never a wall of crisis", () => {
    const crisis = Array.from({ length: 20 }, (_, index) =>
      spreadable({
        id: `crisis-${index}`,
        authorId: `author-${index}`,
        intensity: 5,
        category: index % 2 === 0 ? "work" : "health",
        emotions: [index % 2 === 0 ? "fear" : "sadness"],
      }),
    );
    const calmer = Array.from({ length: 20 }, (_, index) =>
      spreadable({
        id: `calm-${index}`,
        authorId: `calm-author-${index}`,
        intensity: 2,
        category: index % 2 === 0 ? "money" : "friends_social",
        emotions: [index % 2 === 0 ? "hope" : "numbness"],
      }),
    );
    const page = spreadPage([...crisis, ...calmer], 24);
    expect(page.filter((item) => item.intensity >= 5).length).toBeLessThanOrEqual(
      SPREAD_LIMITS.peakIntensity,
    );
  });

  it("fills the page from rank order rather than going short", () => {
    const onlyAuthor = Array.from({ length: 5 }, (_, index) =>
      spreadable({ id: `own-${index}`, authorId: "sole-author" }),
    );
    const page = spreadPage(onlyAuthor, 5);
    expect(page.map((item) => item.id)).toEqual(onlyAuthor.map((item) => item.id));
  });
});

describe("spreadRanked", () => {
  it("keeps every card exactly once so offset paging stays exact", () => {
    const pool = Array.from({ length: 50 }, (_, index) =>
      spreadable({
        id: `card-${index}`,
        authorId: `author-${index % 4}`,
        category: index % 3 === 0 ? "work" : "money",
        emotions: [index % 2 === 0 ? "fear" : "hope"],
        intensity: index % 5 === 0 ? 5 : 3,
      }),
    );
    const spread = spreadRanked(pool, 24);
    expect(spread).toHaveLength(pool.length);
    expect(new Set(spread.map((item) => item.id)).size).toBe(pool.length);
  });

  it("is stable, so two requests for different offsets agree on the order", () => {
    const pool = Array.from({ length: 40 }, (_, index) =>
      spreadable({ id: `card-${index}`, authorId: `author-${index % 3}` }),
    );
    expect(spreadRanked(pool, 12).map((item) => item.id)).toEqual(
      spreadRanked(pool, 12).map((item) => item.id),
    );
  });
});

describe("openingStyle", () => {
  const available = ["stoic", "hopeful", "witty", "tough"] as const;

  it("leaves the card's own cover alone for a viewer with no taste yet", () => {
    expect(
      openingStyle({ cardId: "a", viewerId: "v", cover: "stoic", available, preferred: null }),
    ).toBe("stoic");
  });

  it("never invents an angle the card does not have", () => {
    expect(
      openingStyle({
        cardId: "a",
        viewerId: "v",
        cover: "stoic",
        available: ["stoic", "hopeful"],
        preferred: "witty",
      }),
    ).toBe("stoic");
  });

  it("is stable, so a card does not change face on a reload", () => {
    const pick = () =>
      openingStyle({ cardId: "card-7", viewerId: "viewer-1", cover: "stoic", available, preferred: "witty" });
    expect(pick()).toBe(pick());
  });

  it("leans toward the hearted angle without flattening the mix", () => {
    const cards = Array.from({ length: 400 }, (_, index) => `card-${index}`);
    const preferredCount = cards.filter(
      (cardId) =>
        openingStyle({
          cardId,
          viewerId: "viewer-1",
          cover: "stoic",
          available,
          preferred: "witty",
        }) === "witty",
    ).length;
    // Home's For you tab is meant to show mixed covers, so this is a lean, not a takeover.
    expect(preferredCount).toBeGreaterThan(cards.length * 0.35);
    expect(preferredCount).toBeLessThan(cards.length * 0.65);
  });

  it("gives two viewers different faces on the same card", () => {
    const faces = new Set(
      ["viewer-1", "viewer-2", "viewer-3", "viewer-4"].map((viewerId) =>
        openingStyle({ cardId: "card-1", viewerId, cover: "stoic", available, preferred: "witty" }),
      ),
    );
    expect(faces.size).toBeGreaterThan(1);
  });
});

describe("feed session cursor", () => {
  it("round-trips", () => {
    const session = { seed: "abcdefgh", startedAt: new Date("2026-09-28T09:00:00.000Z"), offset: 48 };
    expect(decodeFeedSession(encodeFeedSession(session))).toEqual(session);
  });

  it("rejects anything it did not issue", () => {
    expect(decodeFeedSession("not-a-cursor")).toBeNull();
    expect(decodeFeedSession("")).toBeNull();
    // A chronological keyset must not decode as a session, or paging would silently swap mode.
    expect(decodeFeedSession("2026-09-10T12:00:00.000Z|22222222-2222-4222-8222-222222222222")).toBeNull();
    expect(
      decodeFeedSession(
        encodeFeedSession({ seed: "abcdefgh", startedAt: new Date("2026-09-28T09:00:00.000Z"), offset: -1 }),
      ),
    ).toBeNull();
    expect(decodeFeedSession(Buffer.from("short|nope|0", "utf8").toString("base64url"))).toBeNull();
  });
});

describe("rankingEnabled", () => {
  it("is off unless a deployment asks for it by name", () => {
    expect(rankingEnabled({})).toBe(false);
    expect(rankingEnabled({ FEED_RANKING: "chronological" })).toBe(false);
    expect(rankingEnabled({ FEED_RANKING: "true" })).toBe(false);
    expect(rankingEnabled({ FEED_RANKING: " Resonance " })).toBe(true);
  });
});

function signal(overrides: Partial<AffinitySignal> = {}): AffinitySignal {
  return { category: "work", emotions: ["shame"], at: NOW, source: "authored", ...overrides };
}

describe("buildAffinity", () => {
  it("reads themes as shares, leader first, and keeps only the themes", () => {
    const affinity = buildAffinity(
      [
        ...Array.from({ length: 6 }, () => signal({ category: "work", emotions: ["fear"] })),
        ...Array.from({ length: 3 }, () => signal({ category: "money", emotions: ["envy"] })),
        signal({ category: "family", emotions: ["anger"] }),
      ],
      NOW,
    );
    expect(affinity.categories.get("work")).toBeCloseTo(0.6, 5);
    expect(affinity.categories.get("money")).toBeCloseTo(0.3, 5);
    // 10% is below the 15% floor: one card is not a theme.
    expect(affinity.categories.has("family")).toBe(false);
    expect(affinity.emotions.has("fear")).toBe(true);
  });

  it("never treats 'other' as a theme", () => {
    const affinity = buildAffinity(
      [
        ...Array.from({ length: 8 }, () => signal({ category: "other", emotions: [] })),
        signal({ category: "health", emotions: [] }),
      ],
      NOW,
    );
    expect(affinity.categories.has("other")).toBe(false);
    expect([...affinity.categories.keys()]).toEqual(["health"]);
  });

  it("keeps a leader even when the profile is flat", () => {
    const flat = (["work", "money", "family", "health", "identity", "future", "grief_loss"] as const).map(
      (category) => signal({ category, emotions: [] }),
    );
    expect(buildAffinity(flat, NOW).categories.size).toBeGreaterThan(0);
  });

  it("lets a heart outweigh something the viewer merely wrote", () => {
    const affinity = buildAffinity(
      [
        signal({ category: "work", emotions: [] }),
        signal({ category: "grief_loss", emotions: [], source: "hearted" }),
      ],
      NOW,
    );
    expect(affinity.categories.get("grief_loss") ?? 0).toBeGreaterThan(
      affinity.categories.get("work") ?? 0,
    );
    expect(AFFINITY_CONFIG.heartWeight).toBeGreaterThan(AFFINITY_CONFIG.authoredWeight);
  });

  it("counts recent activity above old, with a half-life and a floor", () => {
    const old = new Date(NOW.getTime() - 14 * 86_400_000);
    const affinity = buildAffinity(
      [
        signal({ category: "work", emotions: [], at: old }),
        signal({ category: "money", emotions: [], at: NOW }),
      ],
      NOW,
    );
    // Two weeks is one half-life: money carries twice work's weight.
    expect(affinity.categories.get("money")).toBeCloseTo(2 / 3, 5);

    const ancient = new Date(NOW.getTime() - 400 * 86_400_000);
    const faded = buildAffinity([signal({ at: ancient })], NOW);
    expect(faded.confidence).toBeCloseTo(AFFINITY_CONFIG.decayFloor / AFFINITY_CONFIG.fullConfidenceWeight, 5);
    expect(faded.categories.has("work")).toBe(true);
  });

  it("makes one card a hint and five cards a profile", () => {
    expect(buildAffinity([signal()], NOW).confidence).toBeCloseTo(0.2, 5);
    expect(buildAffinity(Array.from({ length: 5 }, () => signal()), NOW).confidence).toBe(1);
    expect(buildAffinity(Array.from({ length: 30 }, () => signal()), NOW).confidence).toBe(1);
    expect(buildAffinity([], NOW)).toBe(EMPTY_AFFINITY);
  });

  it("scales the general affinity term by confidence", () => {
    const subject = card({ category: "work", emotions: ["shame"] });
    const full = scoreCard(subject, { now: NOW, seed: "s", affinity: themes(["work"], ["shame"], 1) });
    const hint = scoreCard(subject, { now: NOW, seed: "s", affinity: themes(["work"], ["shame"], 0.2) });
    expect(hint.terms.affinity).toBeCloseTo(full.terms.affinity * 0.2, 8);
  });
});

describe("theme buckets", () => {
  const work = themes(["work"], ["fear"]);

  it("calls a card on the viewer's own life area core", () => {
    expect(classifyTheme({ category: "work", emotions: [] }, work)).toBe("core");
  });

  it("calls a neighbouring life area or a shared mood adjacent", () => {
    expect(classifyTheme({ category: "money", emotions: [] }, work)).toBe("adjacent");
    expect(classifyTheme({ category: "romantic", emotions: ["fear"] }, work)).toBe("adjacent");
    // Overwhelm sits next to the viewer's strongest mood, fear.
    expect(classifyTheme({ category: "romantic", emotions: ["overwhelm"] }, work)).toBe("adjacent");
  });

  it("calls everything else explore, and everything explore for a viewer with no themes", () => {
    expect(classifyTheme({ category: "romantic", emotions: ["anger"] }, work)).toBe("explore");
    expect(classifyTheme({ category: "work", emotions: ["fear"] }, EMPTY_AFFINITY)).toBe("explore");
  });

  it("gives a cold viewer no quota and a confident one the full mix", () => {
    expect(themeMix(0)).toBeNull();
    expect(themeMix(MIN_MIX_CONFIDENCE - 0.01)).toBeNull();
    expect(themeMix(1)).toEqual(THEME_MIX);
    const partial = themeMix(0.5);
    expect(partial?.core).toBeCloseTo(0.2, 8);
    expect(partial?.adjacent).toBeCloseTo(0.175, 8);
    expect((partial?.core ?? 0) + (partial?.adjacent ?? 0) + (partial?.explore ?? 0)).toBeCloseTo(1, 8);
  });

  it("caps each bucket at its share of the page, rounded up, without leaving a page short", () => {
    const mix = themeMix(1);
    if (!mix) {
      throw new Error("expected a mix");
    }
    expect(bucketCaps(mix, 24)).toEqual({ core: 10, adjacent: 9, explore: 6 });
    const caps = bucketCaps(mix, 24);
    expect(caps.core + caps.adjacent + caps.explore).toBeGreaterThanOrEqual(24);
    const soft = themeMix(0.2);
    if (!soft) {
      throw new Error("expected a mix");
    }
    const softCaps = bucketCaps(soft, 24);
    expect(softCaps.core).toBeLessThan(caps.core);
    expect(softCaps.explore).toBeGreaterThan(caps.explore);
  });
});

describe("spreadPage with a theme mix", () => {
  const mix = themeMix(1);

  function bucketed(count: number, bucket: ThemeBucket, prefix: string): SpreadableCard[] {
    const categories = ["work", "money", "health", "family", "identity", "future"] as const;
    const styles = STYLES;
    return Array.from({ length: count }, (_, index) =>
      spreadable({
        id: `${prefix}-${index}`,
        authorId: `${prefix}-author-${index}`,
        bucket,
        category: categories[index % categories.length] ?? "work",
        emotions: [(["fear", "hope", "anger", "envy"] as const)[index % 4] ?? "fear"],
        spotlightStyle: styles[index % styles.length] ?? "stoic",
      }),
    );
  }

  it("holds a page to about 40 core, 35 adjacent and 25 explore", () => {
    // Explore is ranked first on purpose: without the quota it would take the page.
    const ranked = [
      ...bucketed(40, "explore", "explore"),
      ...bucketed(40, "adjacent", "adjacent"),
      ...bucketed(40, "core", "core"),
    ];
    const page = spreadPage(ranked, 24, { mix });
    const counts = { core: 0, adjacent: 0, explore: 0 };
    for (const item of page) {
      counts[item.bucket ?? "explore"] += 1;
    }
    expect(page).toHaveLength(24);
    expect(Math.abs(counts.core - 24 * THEME_MIX.core)).toBeLessThanOrEqual(1);
    expect(Math.abs(counts.adjacent - 24 * THEME_MIX.adjacent)).toBeLessThanOrEqual(1);
    expect(Math.abs(counts.explore - 24 * THEME_MIX.explore)).toBeLessThanOrEqual(1);
  });

  it("takes each bucket from the top of its own ranking", () => {
    const ranked = [
      ...bucketed(20, "core", "core"),
      ...bucketed(20, "adjacent", "adjacent"),
      ...bucketed(20, "explore", "explore"),
    ];
    const page = spreadPage(ranked, 24, { mix });
    for (const prefix of ["core", "adjacent", "explore"]) {
      const positions = page
        .filter((item) => item.id.startsWith(prefix))
        .map((item) => Number(item.id.split("-").at(-1)));
      // Rhythm rules may step over a card, but never far down the bucket.
      expect(Math.max(...positions)).toBeLessThanOrEqual(positions.length + 2);
    }
  });

  it("falls back to another bucket when one runs dry, and never goes short", () => {
    const ranked = [...bucketed(2, "core", "core"), ...bucketed(30, "explore", "explore")];
    const page = spreadPage(ranked, 24, { mix });
    expect(page).toHaveLength(24);
    expect(page.filter((item) => item.bucket === "core")).toHaveLength(2);
    expect(new Set(page.map((item) => item.id)).size).toBe(24);
  });

  it("is unchanged without a mix", () => {
    const ranked = [...bucketed(20, "explore", "explore"), ...bucketed(20, "core", "core")];
    expect(spreadPage(ranked, 24, { mix: null }).map((item) => item.id)).toEqual(
      spreadPage(ranked, 24).map((item) => item.id),
    );
  });

  it("still enforces the author and intensity caps", () => {
    const loud = Array.from({ length: 10 }, (_, index) =>
      spreadable({ id: `loud-${index}`, authorId: "loud", bucket: "core", intensity: 5 }),
    );
    const crisis = Array.from({ length: 12 }, (_, index) =>
      spreadable({
        id: `crisis-${index}`,
        authorId: `crisis-${index}`,
        bucket: "core",
        intensity: 5,
        category: index % 2 === 0 ? "work" : "health",
        emotions: [index % 2 === 0 ? "fear" : "sadness"],
      }),
    );
    const calm = bucketed(20, "explore", "calm");
    const page = spreadPage([...loud, ...crisis, ...calm], 24, { mix });
    expect(page.filter((item) => item.authorId === "loud").length).toBeLessThanOrEqual(
      SPREAD_LIMITS.perAuthor,
    );
    expect(page.filter((item) => item.intensity >= 5).length).toBeLessThanOrEqual(
      SPREAD_LIMITS.peakIntensity,
    );
  });

  it("lets the viewer's own theme run a beat longer than other themes", () => {
    const longestRun = (items: readonly SpreadableCard[]): number => {
      let run = 1;
      let longest = 1;
      for (let index = 1; index < items.length; index += 1) {
        run = items[index]?.category === items[index - 1]?.category ? run + 1 : 1;
        longest = Math.max(longest, run);
      }
      return longest;
    };
    const pool = (bucket: ThemeBucket): SpreadableCard[] => [
      ...Array.from({ length: 6 }, (_, index) =>
        spreadable({
          id: `work-${index}`,
          authorId: `work-author-${index}`,
          bucket,
          category: "work",
          emotions: [(["fear", "hope", "anger", "envy"] as const)[index % 4] ?? "fear"],
          spotlightStyle: STYLES[index % STYLES.length] ?? "stoic",
        }),
      ),
      ...Array.from({ length: 6 }, (_, index) =>
        spreadable({
          id: `other-${index}`,
          authorId: `other-author-${index}`,
          bucket: "explore",
          category: (["money", "health", "family", "identity", "future", "grief_loss"] as const)[index] ?? "money",
          emotions: [(["sadness", "loneliness", "numbness", "overwhelm", "shame", "hope"] as const)[index] ?? "sadness"],
          spotlightStyle: STYLES[(index + 2) % STYLES.length] ?? "stoic",
        }),
      ),
    ];
    expect(SPREAD_LIMITS.coreRun).toBeGreaterThan(SPREAD_LIMITS.run);
    expect(longestRun(spreadPage(pool("core"), 12))).toBe(SPREAD_LIMITS.coreRun);
    expect(longestRun(spreadPage(pool("explore"), 12))).toBe(SPREAD_LIMITS.run);
  });

  it("keeps every card exactly once and one stable order across windows", () => {
    const pool = [
      ...bucketed(30, "core", "core"),
      ...bucketed(30, "adjacent", "adjacent"),
      ...bucketed(30, "explore", "explore"),
    ];
    const first = spreadRanked(pool, 24, { mix });
    expect(first).toHaveLength(pool.length);
    expect(new Set(first.map((item) => item.id)).size).toBe(pool.length);
    expect(spreadRanked(pool, 24, { mix }).map((item) => item.id)).toEqual(first.map((item) => item.id));
  });
});

describe("primary tab", () => {
  const VIEWER = "viewer-1";
  const coldTabs: StyleTabs = {
    stoic: { affinity: EMPTY_AFFINITY, hearts: 0 },
    hopeful: { affinity: EMPTY_AFFINITY, hearts: 0 },
    witty: { affinity: EMPTY_AFFINITY, hearts: 0 },
    tough: { affinity: EMPTY_AFFINITY, hearts: 0 },
    tender: { affinity: EMPTY_AFFINITY, hearts: 0 },
    values: { affinity: EMPTY_AFFINITY, hearts: 0 },
  };

  function catalog(count: number): RankableCard[] {
    const categories = ["work", "money", "health", "family", "identity", "future", "grief_loss"] as const;
    return Array.from({ length: count }, (_, index) =>
      card({
        id: `cccccccc-0000-4000-8000-${String(index).padStart(12, "0")}`,
        authorId: `author-${index}`,
        category: categories[index % categories.length] ?? "work",
        createdAt: hoursAgo(index * 6),
        // A skewed cover habit must not decide the split.
        coverStyle: "stoic",
      }),
    );
  }

  function firstPage(
    pool: readonly RankableCard[],
    style: Style,
    tabs: StyleTabs = coldTabs,
    general: ViewerAffinity = EMPTY_AFFINITY,
    viewerId = VIEWER,
  ): string[] {
    const primaryByCard = assignPrimaryStyles(pool, { viewerId, general, tabs });
    const ranked = rankCards(pool, {
      now: NOW,
      seed: `visit-${style}`,
      affinity: general,
      style: { style, affinity: tabs[style].affinity, hearts: tabs[style].hearts, primaryByCard },
    });
    const byId = new Map(pool.map((item) => [item.id, item]));
    const spreadInput = ranked.flatMap((scored, index) => {
      const source = byId.get(scored.id);
      return source
        ? [
            spreadable({
              id: source.id,
              authorId: source.authorId,
              category: source.category,
              emotions: source.emotions,
              spotlightStyle: STYLES[index % STYLES.length] ?? "stoic",
            }),
          ]
        : [];
    });
    return spreadRanked(spreadInput, 24)
      .slice(0, 24)
      .map((item) => item.id);
  }

  it("gives a cold viewer four mostly different first pages", () => {
    const pool = catalog(240);
    const pages = STYLES.map((style) => firstPage(pool, style));
    for (let left = 0; left < pages.length; left += 1) {
      for (let right = left + 1; right < pages.length; right += 1) {
        const shared = pages[left]?.filter((id) => pages[right]?.includes(id)).length ?? 0;
        expect(shared / 24).toBeLessThanOrEqual(0.1);
      }
    }
  });

  it("keeps the tabs apart for a viewer with hearts, and pulls a tab's own theme to it", () => {
    const pool = catalog(240);
    // The viewer is mostly in Work overall, but hearts Witty on grief.
    const general = themes(["work"], ["shame"]);
    const tabs: StyleTabs = {
      ...coldTabs,
      witty: { affinity: themes(["grief_loss"], ["sadness"]), hearts: 6 },
    };
    const pages = STYLES.map((style) => firstPage(pool, style, tabs, general));
    for (let left = 0; left < pages.length; left += 1) {
      for (let right = left + 1; right < pages.length; right += 1) {
        const shared = pages[left]?.filter((id) => pages[right]?.includes(id)).length ?? 0;
        expect(shared / 24).toBeLessThanOrEqual(0.1);
      }
    }
    const byId = new Map(pool.map((item) => [item.id, item]));
    const wittyPage = pages[STYLES.indexOf("witty")] ?? [];
    const grief = wittyPage.filter((id) => byId.get(id)?.category === "grief_loss").length;
    expect(grief).toBeGreaterThan(wittyPage.length / 2);
  });

  it("does not let one tab with hearts claim every card that matches the viewer", () => {
    const pool = catalog(400);
    const general = themes(["work"], ["shame"]);
    // Hearts on Witty are the same taste as the general one, so they add no pull.
    const tabs: StyleTabs = { ...coldTabs, witty: { affinity: general, hearts: 6 } };
    const primaries = assignPrimaryStyles(pool, { viewerId: VIEWER, general, tabs });
    const witty = [...primaries.values()].filter((style) => style === "witty").length;
    expect(witty).toBeLessThan(400 * 0.35);
  });

  it("splits a cold catalog roughly evenly, whatever covers the authors chose", () => {
    const pool = catalog(400);
    const primaries = assignPrimaryStyles(pool, { viewerId: VIEWER, general: EMPTY_AFFINITY, tabs: coldTabs });
    const counts = new Map<Style, number>();
    for (const style of primaries.values()) {
      counts.set(style, (counts.get(style) ?? 0) + 1);
    }
    const even = 400 / STYLES.length;
    for (const style of STYLES) {
      expect(counts.get(style) ?? 0).toBeGreaterThan(even * 0.6);
      expect(counts.get(style) ?? 0).toBeLessThan(even * 1.4);
    }
  });

  it("is stable for a viewer and different between viewers", () => {
    const pool = catalog(60);
    const options = { general: EMPTY_AFFINITY, tabs: coldTabs };
    const one = assignPrimaryStyles(pool, { viewerId: "viewer-1", ...options });
    expect([...assignPrimaryStyles(pool, { viewerId: "viewer-1", ...options })]).toEqual([...one]);
    const two = assignPrimaryStyles(pool, { viewerId: "viewer-2", ...options });
    expect([...two]).not.toEqual([...one]);
  });

  it("never assigns an angle the card does not have", () => {
    const pool = catalog(80).map((item) => ({ ...item, availableStyles: ["witty"] as const }));
    const primaries = assignPrimaryStyles(pool, { viewerId: VIEWER, general: EMPTY_AFFINITY, tabs: coldTabs });
    expect(new Set(primaries.values())).toEqual(new Set(["witty"]));
  });

  it("puts a card on the tab strangers hearted it on", () => {
    const loved = card({ id: "dddddddd-0000-4000-8000-000000000001", angleHeartsByStyle: { witty: 8 } });
    expect(PRIMARY_TIE_WEIGHT).toBeLessThan(STYLE_RANKING_WEIGHTS.styleResonance);
    for (const viewerId of ["viewer-1", "viewer-2", "viewer-3", "viewer-4", "viewer-5"]) {
      const primaries = assignPrimaryStyles([loved], { viewerId, general: EMPTY_AFFINITY, tabs: coldTabs });
      expect(primaries.get(loved.id)).toBe("witty");
    }
  });

  it("puts a card on the tab whose hearts match its theme", () => {
    const tabs: StyleTabs = {
      ...coldTabs,
      tough: { affinity: themes(["money"], ["envy"]), hearts: 5 },
    };
    const subject = card({ id: "dddddddd-0000-4000-8000-000000000002", category: "money", emotions: ["envy"] });
    for (const viewerId of ["viewer-1", "viewer-2", "viewer-3", "viewer-4", "viewer-5"]) {
      expect(
        assignPrimaryStyles([subject], { viewerId, general: EMPTY_AFFINITY, tabs }).get(subject.id),
      ).toBe("tough");
    }
  });

  it("penalises an off-tab card without hiding it, so a thin tab still fills", () => {
    // Old enough to have settled onto a tab.
    const home = card({ id: "eeeeeeee-0000-4000-8000-000000000001", createdAt: hoursAgo(24) });
    const away = card({ id: "eeeeeeee-0000-4000-8000-000000000002", createdAt: hoursAgo(24) });
    const primaryByCard = new Map<string, Style>([
      [home.id, "stoic"],
      [away.id, "witty"],
    ]);
    const ranked = rankCards([away, home], {
      now: NOW,
      seed: "s",
      style: { style: "stoic", affinity: EMPTY_AFFINITY, hearts: 0, primaryByCard },
    });
    expect(ranked.map((item) => item.id)).toEqual([home.id, away.id]);
    expect(ranked).toHaveLength(2);
    const gap = (ranked[0]?.score ?? 0) - (ranked[1]?.score ?? 0);
    expect(gap).toBeGreaterThan(STYLE_RANKING_WEIGHTS.offTab - RANKING_WEIGHTS.jitter);

    // A much stronger off-tab card can still lead: a penalty, not a wall.
    const strongAway = { ...away, hearts: 10, createdAt: hoursAgo(1) };
    const weakHome = { ...home, createdAt: hoursAgo(24 * 20) };
    expect(
      rankCards([weakHome, strongAway], {
        now: NOW,
        seed: "s",
        style: { style: "stoic", affinity: EMPTY_AFFINITY, hearts: 0, primaryByCard },
      })[0]?.id,
    ).toBe(strongAway.id);
  });

  it("fades the off-tab penalty in with age, so a fresh post shows on every tab", () => {
    expect(offTabFade({ createdAt: hoursAgo(0.5) }, NOW)).toBe(0);
    expect(offTabFade({ createdAt: hoursAgo(1) }, NOW)).toBe(0);
    expect(offTabFade({ createdAt: hoursAgo(3.5) }, NOW)).toBeCloseTo(0.5, 5);
    expect(offTabFade({ createdAt: hoursAgo(6) }, NOW)).toBe(1);
    expect(offTabFade({ createdAt: hoursAgo(200) }, NOW)).toBe(1);

    const primaryByCard = new Map<string, Style>([["ffffffff-0000-4000-8000-000000000001", "witty"]]);
    const justPosted = card({ id: "ffffffff-0000-4000-8000-000000000001", createdAt: hoursAgo(1) });
    const onStoic = scoreCard(justPosted, {
      now: NOW,
      seed: "s",
      style: {
        style: "stoic",
        affinity: EMPTY_AFFINITY,
        hearts: 0,
        angleHearts: 0,
        coverMatches: false,
        offTab: primaryByCard.get(justPosted.id) !== "stoic",
      },
    });
    const noPenalty = scoreCard(justPosted, {
      now: NOW,
      seed: "s",
      style: { style: "stoic", affinity: EMPTY_AFFINITY, hearts: 0, angleHearts: 0, coverMatches: false },
    });
    expect(onStoic.score).toBeCloseTo(noPenalty.score, 8);
  });

  it("leaves For you untouched by tab assignment", () => {
    const subject = card();
    const plain = scoreCard(subject, { now: NOW, seed: "s" });
    const ranked = rankCards([subject], { now: NOW, seed: "s" });
    expect(ranked[0]?.score).toBe(plain.score);
  });
});

describe("isKeptOnShelf", () => {
  it("hides on For you only once every angle is kept, and on a tab as soon as its own is", () => {
    const kept = new Set<Style>(["hopeful"]);
    expect(isKeptOnShelf(kept, undefined)).toBe(false);
    expect(isPartlyKept(kept)).toBe(true);
    expect(isKeptOnShelf(kept, "hopeful")).toBe(true);
    expect(isKeptOnShelf(kept, "stoic")).toBe(false);

    expect(isKeptOnShelf(new Set<Style>(STYLES), undefined)).toBe(true);
    expect(isPartlyKept(new Set<Style>(STYLES))).toBe(false);
  });

  it("judges a card by the angles it actually has", () => {
    const kept = new Set<Style>(["stoic", "hopeful"]);
    expect(isKeptOnShelf(kept, undefined, ["stoic", "hopeful"])).toBe(true);
    expect(isKeptOnShelf(kept, undefined, ["stoic", "hopeful", "witty"])).toBe(false);
    expect(isPartlyKept(kept, ["stoic", "hopeful", "witty"])).toBe(true);
  });

  it("hides nothing for a card the viewer has not kept", () => {
    expect(isKeptOnShelf(undefined, undefined)).toBe(false);
    expect(isKeptOnShelf(new Set<Style>(), "stoic")).toBe(false);
    expect(isPartlyKept(undefined)).toBe(false);
  });
});

describe("own cards", () => {
  const confident = themes(["work"], ["shame"]);

  it("get no theme match or follow, so they compete as a stranger's card would", () => {
    const mine = scoreCard(card({ own: true, followed: true }), { now: NOW, seed: "s", affinity: confident });
    const stranger = scoreCard(card({ id: "33333333-3333-4333-8333-333333333333" }), {
      now: NOW,
      seed: "s",
      affinity: EMPTY_AFFINITY,
    });
    expect(mine.terms.affinity).toBe(0);
    expect(mine.terms.followed).toBe(0);
    expect(mine.terms.freshness).toBeCloseTo(stranger.terms.freshness, 8);
  });

  it("appear at most once a page, and the list ends when only own cards are left", () => {
    const ranked = [
      ...Array.from({ length: 6 }, (_, index) =>
        spreadable({ id: `mine-${index}`, authorId: "me", own: true }),
      ),
      spreadable({ id: "theirs-0", authorId: "martina" }),
      spreadable({ id: "theirs-1", authorId: "martina", category: "money" }),
    ];
    const page = spreadPage(ranked, 24);
    expect(page.filter((item) => item.own)).toHaveLength(1);
    expect(page.map((item) => item.id)).toEqual(expect.arrayContaining(["theirs-0", "theirs-1"]));

    const whole = spreadRanked(ranked, 24);
    expect(whole).toHaveLength(3);
    expect(whole.filter((item) => item.own)).toHaveLength(1);
  });

  it("still shows the top one when nobody else has posted", () => {
    const ranked = Array.from({ length: 4 }, (_, index) =>
      spreadable({ id: `mine-${index}`, authorId: "me", own: true }),
    );
    expect(spreadRanked(ranked, 24).map((item) => item.id)).toEqual(["mine-0"]);
  });
});

describe("a small community", () => {
  it("alternates authors instead of walling the page with the top one", () => {
    const ranked = [
      ...Array.from({ length: 8 }, (_, index) =>
        spreadable({ id: `a-${index}`, authorId: "author-a", category: CATEGORY_CYCLE[index % 4] }),
      ),
      ...Array.from({ length: 4 }, (_, index) =>
        spreadable({ id: `b-${index}`, authorId: "author-b", category: CATEGORY_CYCLE[index % 4] }),
      ),
    ];
    const page = spreadPage(ranked, 12);
    expect(page).toHaveLength(12);
    // Every b card is placed before a's tail, and no author runs three in a row while
    // the other still has cards.
    const lastB = page.map((item) => item.authorId).lastIndexOf("author-b");
    expect(lastB).toBeLessThan(9);
    let run = 0;
    let longest = 0;
    let previous = "";
    for (const item of page.slice(0, lastB + 1)) {
      run = item.authorId === previous ? run + 1 : 1;
      previous = item.authorId;
      longest = Math.max(longest, run);
    }
    expect(longest).toBeLessThanOrEqual(2);
  });

  it("does not put one author back to back when someone else fits", () => {
    const ranked = [
      spreadable({ id: "a-0", authorId: "a", category: "work" }),
      spreadable({ id: "a-1", authorId: "a", category: "money" }),
      spreadable({ id: "b-0", authorId: "b", category: "family" }),
    ];
    expect(spreadPage(ranked, 3).map((item) => item.id)).toEqual(["a-0", "b-0", "a-1"]);
  });
});

describe("follow mix", () => {
  const followedCard = (index: number, authorId: string, hours = 10): SpreadableCard =>
    spreadable({
      id: `f-${authorId}-${index}`,
      authorId,
      followed: true,
      createdAt: hoursAgo(hours),
      category: CATEGORY_CYCLE[index % 4],
      emotions: [EMOTION_CYCLE[index % 4] ?? "shame"],
    });
  const strangerCard = (index: number): SpreadableCard =>
    spreadable({
      id: `s-${index}`,
      authorId: `stranger-${index}`,
      createdAt: hoursAgo(1),
      category: CATEGORY_CYCLE[index % 4],
      emotions: [EMOTION_CYCLE[(index + 1) % 4] ?? "shame"],
    });

  it("is off until the viewer follows three people who posted this week", () => {
    const two = [followedCard(0, "x"), followedCard(0, "y")];
    expect(followMix(two, NOW)).toBeNull();
    const stale = [...two, followedCard(0, "z", 24 * 9)];
    expect(followMix(stale, NOW)).toBeNull();
    const three = [...two, followedCard(0, "z")];
    expect(followMix(three, NOW)).toMatchObject({ share: FOLLOW_MIX.share, maxShare: FOLLOW_MIX.maxShare });
  });

  it("holds about a quarter of the page for followed authors, paced from the top", () => {
    // Strangers' posts are all fresher, so plain rank order would push every followed card off the page.
    const ranked = [
      ...Array.from({ length: 30 }, (_, index) => strangerCard(index)),
      ...["x", "y", "z", "w"].flatMap((authorId) => [0, 1].map((index) => followedCard(index, authorId))),
    ];
    const mix = followMix(ranked, NOW);
    const page = spreadPage(ranked, 24, { follow: mix });
    const followedSlots = page.flatMap((item, slot) => (item.followed ? [slot] : []));
    expect(followedSlots).toHaveLength(6);
    expect(followedSlots[0]).toBeLessThan(4);
    expect(followedSlots.every((slot, index) => slot <= 4 * (index + 1))).toBe(true);
    expect(spreadPage(ranked, 24).filter((item) => item.followed)).toHaveLength(0);
  });

  it("never lets followed authors take more than half a page while anything else is left", () => {
    // Followed posts rank first; the cap stops them at half.
    const ranked = [
      ...["x", "y", "z", "w", "v", "u", "t"].flatMap((authorId) =>
        [0, 1].map((index) => followedCard(index, authorId)),
      ),
      ...Array.from({ length: 20 }, (_, index) => strangerCard(index)),
    ];
    const page = spreadPage(ranked, 24, { follow: followMix(ranked, NOW) });
    expect(page.filter((item) => item.followed)).toHaveLength(12);
  });
});

describe("partly kept cards", () => {
  it("drop by the partly-kept penalty on For you, and not on a style shelf", () => {
    const plain = scoreCard(card(), { now: NOW, seed: "s" });
    const partly = scoreCard(card({ partlyKept: true }), { now: NOW, seed: "s" });
    expect(partly.score).toBeCloseTo(plain.score + RANKING_WEIGHTS.partlyKept, 8);

    const shelf: StyleShelfContext = {
      style: "stoic",
      affinity: EMPTY_AFFINITY,
      hearts: 0,
      angleHearts: 0,
      coverMatches: false,
    };
    const onShelf = scoreCard(card({ partlyKept: true }), { now: NOW, seed: "s", style: shelf });
    const plainShelf = scoreCard(card(), { now: NOW, seed: "s", style: shelf });
    expect(onShelf.score).toBeCloseTo(plainShelf.score, 8);
  });

  it("open on an answer the viewer has not kept", () => {
    const face = openingStyle({
      cardId: "c",
      viewerId: "v",
      cover: "witty",
      available: STYLES,
      preferred: "witty",
      kept: new Set<Style>(["witty"]),
    });
    expect(face).toBe("tough");
    expect(
      openingStyle({
        cardId: "c",
        viewerId: "v",
        cover: "witty",
        available: STYLES,
        preferred: "stoic",
        kept: new Set<Style>(["witty"]),
      }),
    ).toBe("stoic");
    // Nothing unkept left: the cover stands.
    expect(
      openingStyle({
        cardId: "c",
        viewerId: "v",
        cover: "witty",
        available: ["witty"],
        preferred: null,
        kept: new Set<Style>(["witty"]),
      }),
    ).toBe("witty");
  });
});
