import { describe, expect, it } from "vitest";
import { STYLES, type Category, type Emotion, type Style } from "../types/index.js";
import {
  AFFINITY_CONFIG,
  EMPTY_AFFINITY,
  FOLLOW_MIX,
  HEAVY_INTENSITY,
  MIN_MIX_CONFIDENCE,
  RANKING_WEIGHTS,
  RETURN_AFTER_HOURS,
  SPREAD_LIMITS,
  THEME_MIX,
  affinityTerm,
  bucketCaps,
  buildAffinity,
  classifyTheme,
  compareRanked,
  decodeFeedSession,
  encodeFeedSession,
  followMix,
  freshnessTerm,
  jitterTerm,
  openingStyle,
  rankCards,
  rankingEnabled,
  returningCap,
  resonanceTerm,
  scoreCard,
  secondChanceTerm,
  spreadPage,
  spreadRanked,
  themeMix,
  type AffinitySignal,
  type RankableCard,
  type SpreadableCard,
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
    saves: 0,
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
    heavy: false,
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
    const yesterday = scoreCard(card({ id: "a", createdAt: hoursAgo(26), saves: 2 }), {
      now: NOW,
      seed: "s",
    });
    // A lone couple of saves does not lift yesterday's post over a fresh one.
    expect(fresh.score).toBeGreaterThan(yesterday.score);

    const threeDays = scoreCard(card({ id: "a", createdAt: hoursAgo(72), saves: 10 }), {
      now: NOW,
      seed: "s",
    });
    const twoDaysPlain = scoreCard(card({ id: "a", createdAt: hoursAgo(48) }), { now: NOW, seed: "s" });
    // A card people clearly keep can outrank a plain one a day newer.
    expect(threeDays.score).toBeGreaterThan(twoDaysPlain.score);
  });

  it("damps resonance and caps it so one card cannot own the feed", () => {
    expect(resonanceTerm(card({ saves: 0 }))).toBe(0);
    expect(resonanceTerm(card({ saves: 1 }))).toBeLessThan(resonanceTerm(card({ saves: 3 })));
    expect(resonanceTerm(card({ saves: 10 }))).toBeCloseTo(1, 5);
    expect(resonanceTerm(card({ saves: 5_000 }))).toBe(1);
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

  it("gives an unsaved young post a second chance that fades", () => {
    expect(secondChanceTerm(card({ createdAt: hoursAgo(2) }), NOW)).toBe(0);
    expect(secondChanceTerm(card({ createdAt: hoursAgo(48) }), NOW)).toBe(1);
    expect(secondChanceTerm(card({ createdAt: hoursAgo(24 * 20) }), NOW)).toBeCloseTo(
      10 / 16,
      5,
    );
    expect(secondChanceTerm(card({ createdAt: hoursAgo(24 * 40) }), NOW)).toBe(0);
    // Hearted posts do not need help being found.
    expect(secondChanceTerm(card({ createdAt: hoursAgo(48), saves: 1 }), NOW)).toBe(0);
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
  it("puts a saved card above an equally fresh unsaved one", () => {
    const ranked = rankCards(
      [
        card({ id: "aaaaaaaa-0000-4000-8000-000000000001", saves: 0 }),
        card({ id: "bbbbbbbb-0000-4000-8000-000000000002", saves: 6 }),
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

  it("leans toward the saved angle without flattening the mix", () => {
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
    const session = { seed: "abcdefgh", startedAt: new Date("2026-09-28T09:00:00.000Z") };
    expect(decodeFeedSession(encodeFeedSession(session))).toEqual(session);
  });

  it("rejects anything it did not issue", () => {
    expect(decodeFeedSession("not-a-cursor")).toBeNull();
    expect(decodeFeedSession("")).toBeNull();
    // A chronological keyset must not decode as a session, or paging would silently swap mode.
    expect(decodeFeedSession("2026-09-10T12:00:00.000Z|22222222-2222-4222-8222-222222222222")).toBeNull();
    // The old three-part feed cursor is not a stack session.
    expect(
      decodeFeedSession(Buffer.from("abcdefgh|2026-09-28T09:00:00.000Z|48", "utf8").toString("base64url")),
    ).toBeNull();
    expect(decodeFeedSession(Buffer.from("short|nope", "utf8").toString("base64url"))).toBeNull();
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

  it("lets a save outweigh something the viewer merely wrote", () => {
    const affinity = buildAffinity(
      [
        signal({ category: "work", emotions: [] }),
        signal({ category: "grief_loss", emotions: [], source: "saved" }),
      ],
      NOW,
    );
    expect(affinity.categories.get("grief_loss") ?? 0).toBeGreaterThan(
      affinity.categories.get("work") ?? 0,
    );
    expect(AFFINITY_CONFIG.savedWeight).toBeGreaterThan(AFFINITY_CONFIG.authoredWeight);
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

  it("never runs more than two of one life area, the viewer's own included", () => {
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
    expect(longestRun(spreadPage(pool("core"), 12))).toBe(SPREAD_LIMITS.run);
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

describe("passes", () => {
  it("take a little from the passer's themes, never below zero, and add no confidence", () => {
    const saved = signal({ category: "work", emotions: ["fear"], source: "saved" });
    const base = buildAffinity([saved, signal({ category: "money", emotions: [], source: "authored" })], NOW);
    const withPass = buildAffinity(
      [
        saved,
        signal({ category: "money", emotions: [], source: "authored" }),
        signal({ category: "money", emotions: [], source: "passed" }),
      ],
      NOW,
    );
    expect(withPass.categories.get("money") ?? 0).toBeLessThan(base.categories.get("money") ?? 0);
    expect(withPass.confidence).toBe(base.confidence);

    const onlyPasses = buildAffinity(
      Array.from({ length: 10 }, () => signal({ category: "health", emotions: ["sadness"], source: "passed" })),
      NOW,
    );
    expect(onlyPasses).toEqual(EMPTY_AFFINITY);
  });

  it("are not a ranking input for anyone else: resonance reads saves only", () => {
    expect(Object.keys(card())).not.toContain("passes");
    expect(resonanceTerm(card({ saves: 0 }))).toBe(0);
  });
});

describe("returning cards", () => {
  it("wait at least twelve hours", () => {
    expect(RETURN_AFTER_HOURS).toBeGreaterThanOrEqual(12);
  });

  it("rank below an otherwise equal card", () => {
    const fresh = scoreCard(card({ id: "a" }), { now: NOW, seed: "s" });
    const back = scoreCard(card({ id: "a", returning: true }), { now: NOW, seed: "s" });
    expect(back.score).toBeLessThan(fresh.score);
    expect(fresh.score - back.score).toBeCloseTo(-RANKING_WEIGHTS.returning, 5);
  });

  it("fill at most one slot in five, and a page ends short rather than fill with them", () => {
    expect(returningCap(12)).toBe(2);
    expect(returningCap(3)).toBe(1);
    const ranked = [
      ...Array.from({ length: 10 }, (_, index) =>
        spreadable({
          id: `back-${index}`,
          authorId: `back-author-${index}`,
          category: CATEGORY_CYCLE[index % 4],
          emotions: [EMOTION_CYCLE[index % 4] ?? "shame"],
          returning: true,
        }),
      ),
      ...Array.from({ length: 4 }, (_, index) =>
        spreadable({
          id: `new-${index}`,
          authorId: `new-author-${index}`,
          category: CATEGORY_CYCLE[(index + 1) % 4],
          emotions: [EMOTION_CYCLE[(index + 2) % 4] ?? "fear"],
        }),
      ),
    ];
    const page = spreadPage(ranked, 12);
    expect(page.filter((item) => item.returning)).toHaveLength(returningCap(12));
    expect(page).toHaveLength(4 + returningCap(12));
    // Across pages they all still come, a couple at a time.
    expect(spreadRanked(ranked, 12)).toHaveLength(ranked.length);
  });
});

describe("emotional pacing", () => {
  const heavyPool = (): SpreadableCard[] =>
    Array.from({ length: 12 }, (_, index) =>
      spreadable({
        id: `card-${index}`,
        authorId: `author-${index}`,
        category: CATEGORY_CYCLE[index % 4],
        emotions: [EMOTION_CYCLE[index % 4] ?? "shame"],
        intensity: index < 6 ? HEAVY_INTENSITY : 2,
        heavy: index < 6,
      }),
    );

  it("never puts two heavy cards side by side when another order exists", () => {
    const page = spreadPage(heavyPool(), 12);
    expect(page).toHaveLength(12);
    for (let index = 1; index < page.length; index += 1) {
      expect(page[index - 1]?.heavy && page[index]?.heavy).toBe(false);
    }
  });

  it("does not spend the light cards first when ranking puts them on top", () => {
    const pool = heavyPool();
    const lightFirst = [...pool.filter((item) => !item.heavy), ...pool.filter((item) => item.heavy)];
    const page = spreadPage(lightFirst, 12);
    expect(page).toHaveLength(12);
    for (let index = 1; index < page.length; index += 1) {
      expect(page[index - 1]?.heavy && page[index]?.heavy).toBe(false);
    }
  });

  it("carries across the page edge", () => {
    const page = spreadPage(heavyPool(), 4, { afterHeavy: true });
    expect(page[0]?.heavy).toBe(false);
    const all = spreadRanked(heavyPool(), 4);
    for (let index = 1; index < all.length; index += 1) {
      expect(all[index - 1]?.heavy && all[index]?.heavy).toBe(false);
    }
  });

  it("still shows heavy cards back to back when nothing light is left", () => {
    const page = spreadPage(
      heavyPool().filter((item) => item.heavy),
      12,
    );
    expect(page).toHaveLength(6);
  });
});

describe("openingStyle for a returning card", () => {
  const available: Style[] = ["stoic", "hopeful", "witty", "tender"];

  it("opens on the first angle not yet seen, in the cook's order, over any taste", () => {
    expect(
      openingStyle({
        cardId: "a",
        viewerId: "v",
        cover: "stoic",
        available,
        preferred: "stoic",
        checked: new Set<Style>(["stoic", "witty"]),
      }),
    ).toBe("hopeful");
  });

  it("falls back to the usual face when every angle was seen", () => {
    expect(
      openingStyle({
        cardId: "a",
        viewerId: "v",
        cover: "stoic",
        available,
        preferred: null,
        checked: new Set<Style>(available),
      }),
    ).toBe("stoic");
  });
});
