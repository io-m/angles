import { describe, expect, it } from "vitest";
import {
  EMPTY_AFFINITY,
  RANKING_WEIGHTS,
  SPREAD_LIMITS,
  STYLE_AFFINITY_FULL_HEARTS,
  STYLE_RANKING_WEIGHTS,
  affinityTerm,
  blendedAffinityTerm,
  compareRanked,
  decodeFeedSession,
  encodeFeedSession,
  freshnessTerm,
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
  type RankableCard,
  type SpreadableCard,
  type StyleShelfContext,
} from "./feedRanking.js";

const NOW = new Date("2026-09-28T12:00:00.000Z");

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
  it("decays freshness over days, not hours", () => {
    expect(freshnessTerm(card({ createdAt: NOW }), NOW)).toBeCloseTo(1, 5);
    // A day old is still most of its freshness: this app has no news cycle.
    expect(freshnessTerm(card({ createdAt: hoursAgo(24) }), NOW)).toBeGreaterThan(0.75);
    expect(freshnessTerm(card({ createdAt: hoursAgo(96) }), NOW)).toBeCloseTo(Math.exp(-1), 5);
    expect(freshnessTerm(card({ createdAt: hoursAgo(24 * 30) }), NOW)).toBeLessThan(0.01);
  });

  it("damps resonance and caps it so one card cannot own the feed", () => {
    expect(resonanceTerm(card({ hearts: 0 }))).toBe(0);
    expect(resonanceTerm(card({ hearts: 1 }))).toBeLessThan(resonanceTerm(card({ hearts: 3 })));
    expect(resonanceTerm(card({ hearts: 10 }))).toBeCloseTo(1, 5);
    expect(resonanceTerm(card({ hearts: 5_000 }))).toBe(1);
  });

  it("scores affinity from the viewer's own life areas and moods", () => {
    const affinity = {
      categories: new Set(["work"] as const),
      emotions: new Set(["shame", "fear"] as const),
    };
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
    const affinity = {
      categories: new Set(["grief_loss"] as const),
      emotions: new Set(["sadness"] as const),
    };
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
        createdAt: hoursAgo(index * 4),
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
  const styleAffinity = {
    categories: new Set(["work"] as const),
    emotions: new Set(["shame"] as const),
  };

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

  it("leaves All scoring untouched when no style shelf is requested", () => {
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
    const specific = {
      categories: new Set(["work"] as const),
      emotions: new Set(["shame", "fear"] as const),
    };
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
        createdAt: hoursAgo(index * 4),
      }),
    );
    const stoic = rankCards(pool, {
      now: NOW,
      seed: "shared-seed",
      style: { style: "stoic", affinity: EMPTY_AFFINITY, hearts: 0 },
    }).map((item) => item.id);
    const humorous = rankCards(pool, {
      now: NOW,
      seed: "shared-seed",
      style: { style: "humorous", affinity: EMPTY_AFFINITY, hearts: 0 },
    }).map((item) => item.id);
    expect(
      rankCards(pool, {
        now: NOW,
        seed: "shared-seed",
        style: { style: "stoic", affinity: EMPTY_AFFINITY, hearts: 0 },
      }).map((item) => item.id),
    ).toEqual(stoic);
    expect(humorous).not.toEqual(stoic);
  });

  it("gives a style shelf a different head from All when that angle is the strong one", () => {
    const stoicId = "aaaaaaaa-0000-4000-8000-000000000001";
    const humorousId = "bbbbbbbb-0000-4000-8000-000000000002";
    const pool = [
      card({ id: stoicId, coverStyle: "stoic", createdAt: hoursAgo(48) }),
      card({ id: humorousId, coverStyle: "humorous", createdAt: hoursAgo(1) }),
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
    const humorous = rankCards(
      pool.map((item) => ({ ...item, angleHearts: item.id === humorousId ? 8 : 0 })),
      {
        now: NOW,
        seed: "seed",
        style: { style: "humorous", affinity: EMPTY_AFFINITY, hearts: 0 },
      },
    );
    expect(stoic[0]?.id).toBe(stoicId);
    expect(humorous[0]?.id).toBe(humorousId);
    expect(stoic.map((item) => item.id)).not.toEqual(humorous.map((item) => item.id));
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
        spotlightStyle: "humorous",
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
  const available = ["stoic", "optimistic", "humorous", "tough_love"] as const;

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
        available: ["stoic", "optimistic"],
        preferred: "humorous",
      }),
    ).toBe("stoic");
  });

  it("is stable, so a card does not change face on a reload", () => {
    const pick = () =>
      openingStyle({ cardId: "card-7", viewerId: "viewer-1", cover: "stoic", available, preferred: "humorous" });
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
          preferred: "humorous",
        }) === "humorous",
    ).length;
    // Home's All tab is meant to show mixed covers, so this is a lean, not a takeover.
    expect(preferredCount).toBeGreaterThan(cards.length * 0.35);
    expect(preferredCount).toBeLessThan(cards.length * 0.65);
  });

  it("gives two viewers different faces on the same card", () => {
    const faces = new Set(
      ["viewer-1", "viewer-2", "viewer-3", "viewer-4"].map((viewerId) =>
        openingStyle({ cardId: "card-1", viewerId, cover: "stoic", available, preferred: "humorous" }),
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
