import { createHash } from "node:crypto";
import { type Category, type Emotion, type Style } from "../types/index.js";

/**
 * Resonance ranking for the Home stack.
 *
 * What it optimizes, in order: recency (a newer post beats an older one unless saves or
 * themes clearly say otherwise), recognition (thoughts near the themes this viewer writes
 * and saves, held to a core/adjacent/explore page mix so it never becomes an echo), relief
 * (cards strangers kept), a different order every visit, and exposure for posts nobody
 * has found yet.
 *
 * What it refuses to optimize: dwell time, session length, and distress. Intensity is
 * capped and paced by the spread pass, never rewarded. A pass never counts against a
 * card: heavy cards are passed more, and they must not lose to light ones for it.
 */
export const RANKING_WEIGHTS = {
  freshness: 2.0,
  resonance: 0.8,
  affinity: 0.7,
  followed: 0.6,
  secondChance: 0.25,
  jitter: 0.15,
  /**
   * A card this viewer passed once, back on an angle they never saw. About a day of
   * freshness below a new card, so a stack is never mostly reruns.
   */
  returning: -0.75,
} as const;

/** How a viewer's themes are learned. A save says more about what someone reads than what
 * they happened to write; a pass is a quiet "less of this", for this viewer only. */
export const AFFINITY_CONFIG = {
  halfLifeDays: 14,
  /** Old taste fades but never vanishes, so a returning viewer is not treated as new. */
  decayFloor: 0.1,
  authoredWeight: 1,
  savedWeight: 1.5,
  passedWeight: -0.3,
  /** Decayed signal weight at which the themes are fully trusted. Passes add none. */
  fullConfidenceWeight: 5,
  maxCategories: 3,
  minCategoryShare: 0.15,
  maxEmotions: 5,
  minEmotionShare: 0.1,
} as const;

/**
 * Freshness decay scale in hours. One day: a post from this morning is worth most of a
 * new one, yesterday's about a third, and after three days time no longer separates
 * posts, which leaves saves, themes and follows to order them.
 */
const FRESHNESS_SCALE_HOURS = 24;

/** Saves where resonance saturates, so one popular card cannot own the stack. */
const RESONANCE_SATURATION = 10;

/** A post gets a leg up while it is this young and still unsaved. */
const SECOND_CHANCE_DAYS = { start: 1, full: 14, end: 30 } as const;

/** A passed card can come back only once this long has gone by since the pass. */
export const RETURN_AFTER_HOURS = 12;

export type RankableCard = {
  id: string;
  authorId: string;
  createdAt: Date;
  category: Category;
  emotions: readonly Emotion[];
  /** Distinct other people who saved it. The viewer never counts. */
  saves: number;
  followed: boolean;
  /** Passed once by this viewer and back on an angle they never saw. */
  returning?: boolean;
};

/**
 * The life areas and moods a viewer is mostly in, as shares of their recent activity.
 * The maps hold only the themes (top few above a minimum share), never the long tail.
 * `confidence` is how much evidence backs them: one card is a hint, not a profile.
 */
export type ViewerAffinity = {
  categories: ReadonlyMap<Category, number>;
  emotions: ReadonlyMap<Emotion, number>;
  confidence: number;
};

export const EMPTY_AFFINITY: ViewerAffinity = {
  categories: new Map<Category, number>(),
  emotions: new Map<Emotion, number>(),
  confidence: 0,
};

/** One thing a viewer wrote, saved, or passed, reduced to what theme learning needs. */
export type AffinitySignal = {
  category: Category;
  emotions: readonly Emotion[];
  at: Date;
  source: "authored" | "saved" | "passed";
};

function topShares<T extends string>(
  weights: ReadonlyMap<T, number>,
  keep: number,
  minShare: number,
): Map<T, number> {
  let sum = 0;
  for (const weight of weights.values()) {
    sum += weight;
  }
  const shares = new Map<T, number>();
  if (sum <= 0) {
    return shares;
  }
  const ordered = [...weights.entries()]
    .filter(([, weight]) => weight > 0)
    .sort((left, right) => right[1] - left[1] || (left[0] < right[0] ? -1 : 1));
  for (const [key, weight] of ordered.slice(0, keep)) {
    const share = weight / sum;
    // A flat profile still has a leader, so the top entry always survives.
    if (shares.size === 0 || share >= minShare) {
      shares.set(key, share);
    }
  }
  return shares;
}

function signalWeight(source: AffinitySignal["source"]): number {
  switch (source) {
    case "saved":
      return AFFINITY_CONFIG.savedWeight;
    case "passed":
      return AFFINITY_CONFIG.passedWeight;
    case "authored":
      return AFFINITY_CONFIG.authoredWeight;
  }
}

/**
 * Themes from recent activity. Each signal decays with a 14-day half-life (floored, so
 * old taste fades without vanishing), saves count more than writing, a pass subtracts a
 * little from that card's themes, and `other` is never a theme: it is where nothing fit.
 * A theme never goes below zero, so passing cannot make a life area unreachable; the
 * explore share of each page still reaches it.
 */
export function buildAffinity(signals: readonly AffinitySignal[], now: Date): ViewerAffinity {
  const categoryWeights = new Map<Category, number>();
  const emotionWeights = new Map<Emotion, number>();
  let total = 0;

  for (const signal of signals) {
    const ageDays = Math.max(0, (now.getTime() - signal.at.getTime()) / 86_400_000);
    const decay = Math.max(
      AFFINITY_CONFIG.decayFloor,
      0.5 ** (ageDays / AFFINITY_CONFIG.halfLifeDays),
    );
    const weight = signalWeight(signal.source) * decay;
    if (weight > 0) {
      total += weight;
    }
    if (signal.category !== "other") {
      categoryWeights.set(signal.category, (categoryWeights.get(signal.category) ?? 0) + weight);
    }
    for (const emotion of new Set(signal.emotions)) {
      emotionWeights.set(emotion, (emotionWeights.get(emotion) ?? 0) + weight);
    }
  }

  const floored = <T>(weights: Map<T, number>): Map<T, number> =>
    new Map([...weights].map(([key, weight]) => [key, Math.max(0, weight)]));
  const categories = topShares(
    floored(categoryWeights),
    AFFINITY_CONFIG.maxCategories,
    AFFINITY_CONFIG.minCategoryShare,
  );
  const emotions = topShares(
    floored(emotionWeights),
    AFFINITY_CONFIG.maxEmotions,
    AFFINITY_CONFIG.minEmotionShare,
  );
  if (categories.size === 0 && emotions.size === 0) {
    return EMPTY_AFFINITY;
  }
  return {
    categories,
    emotions,
    confidence: Math.min(1, total / AFFINITY_CONFIG.fullConfidenceWeight),
  };
}

/** A theme's strength relative to the viewer's strongest one, so the top theme is 1. */
function relativeShare<T>(shares: ReadonlyMap<T, number>, key: T): number {
  const share = shares.get(key);
  if (share === undefined) {
    return 0;
  }
  let top = 0;
  for (const value of shares.values()) {
    top = Math.max(top, value);
  }
  return top > 0 ? share / top : 0;
}

export type RankingTerms = {
  freshness: number;
  resonance: number;
  affinity: number;
  followed: number;
  secondChance: number;
  jitter: number;
  returning: number;
};

export type ScoredCard = { id: string; score: number; terms: RankingTerms };

export function freshnessTerm(card: RankableCard, now: Date): number {
  const ageHours = Math.max(0, (now.getTime() - card.createdAt.getTime()) / 3_600_000);
  return Math.exp(-ageHours / FRESHNESS_SCALE_HOURS);
}

/** Distinct people who saved the card, damped and capped. */
export function resonanceTerm(card: RankableCard): number {
  if (card.saves <= 0) {
    return 0;
  }
  const scaled = Math.log1p(card.saves) / Math.log1p(RESONANCE_SATURATION);
  return Math.min(1, scaled);
}

/**
 * How close a card sits to the viewer's themes, graded by how strong each theme is.
 * A life area is worth more than a mood. The viewer's confidence is applied by the caller.
 */
export function affinityTerm(card: RankableCard, affinity: ViewerAffinity): number {
  const category = relativeShare(affinity.categories, card.category);
  let mood = 0;
  for (const emotion of new Set(card.emotions)) {
    mood += relativeShare(affinity.emotions, emotion);
  }
  return 0.6 * category + 0.4 * Math.min(1, mood / 2);
}

/**
 * Exposure for a post nobody has kept yet. In a community this small, an author whose
 * card gets no reads stops posting, so this is fairness rather than quality.
 */
export function secondChanceTerm(card: RankableCard, now: Date): number {
  if (card.saves > 0) {
    return 0;
  }
  const ageDays = (now.getTime() - card.createdAt.getTime()) / 86_400_000;
  if (ageDays < SECOND_CHANCE_DAYS.start || ageDays >= SECOND_CHANCE_DAYS.end) {
    return 0;
  }
  if (ageDays <= SECOND_CHANCE_DAYS.full) {
    return 1;
  }
  const remaining = SECOND_CHANCE_DAYS.end - ageDays;
  return remaining / (SECOND_CHANCE_DAYS.end - SECOND_CHANCE_DAYS.full);
}

/**
 * The variety knob: stable for a visit, different on the next. Deterministic so paging
 * cannot shuffle under the reader — `ORDER BY random()` would make offsets meaningless.
 */
export function jitterTerm(cardId: string, seed: string): number {
  const digest = createHash("sha256").update(`${seed}:${cardId}`).digest();
  return digest.readUInt32BE(0) / 0x1_0000_0000;
}

export function scoreCard(
  card: RankableCard,
  options: { now: Date; seed: string; affinity?: ViewerAffinity },
): ScoredCard {
  const affinity = options.affinity ?? EMPTY_AFFINITY;
  const terms: RankingTerms = {
    freshness: freshnessTerm(card, options.now),
    resonance: resonanceTerm(card),
    affinity: affinityTerm(card, affinity) * affinity.confidence,
    followed: card.followed ? 1 : 0,
    secondChance: secondChanceTerm(card, options.now),
    jitter: jitterTerm(card.id, options.seed),
    returning: card.returning ? 1 : 0,
  };

  let score = 0;
  for (const key of Object.keys(RANKING_WEIGHTS) as (keyof RankingTerms)[]) {
    score += RANKING_WEIGHTS[key] * terms[key];
  }
  return { id: card.id, score, terms };
}

/** Highest first, ties broken by id so one seed always produces one order. */
export function compareRanked(left: ScoredCard, right: ScoredCard): number {
  return right.score - left.score || (left.id < right.id ? 1 : -1);
}

export function rankCards(
  cards: readonly RankableCard[],
  options: { now: Date; seed: string; affinity?: ViewerAffinity },
): ScoredCard[] {
  return cards.map((card) => scoreCard(card, options)).sort(compareRanked);
}

/**
 * How much of a page follows the viewer's themes. Core is their own life areas, adjacent
 * is next door (a neighbouring life area or a shared mood), explore is everything else.
 * Ranking orders cards inside a bucket; the mix decides how many of each a page holds.
 */
export const THEME_MIX = { core: 0.4, adjacent: 0.35, explore: 0.25 } as const;

/** Below this confidence the viewer has too little history for a quota. */
export const MIN_MIX_CONFIDENCE = 0.2;

export type ThemeBucket = keyof typeof THEME_MIX;

export type ThemeMix = Readonly<Record<ThemeBucket, number>>;

function symmetricPairs<T extends string>(pairs: readonly (readonly [T, T])[]): Map<T, Set<T>> {
  const map = new Map<T, Set<T>>();
  const link = (from: T, to: T): void => {
    const set = map.get(from) ?? new Set<T>();
    set.add(to);
    map.set(from, set);
  };
  for (const [left, right] of pairs) {
    link(left, right);
    link(right, left);
  }
  return map;
}

/** Life areas that people tend to carry together. Deliberately small and editable. */
export const CATEGORY_ADJACENCY: ReadonlyMap<Category, ReadonlySet<Category>> = symmetricPairs<Category>([
  ["work", "money"],
  ["work", "future"],
  ["work", "self_worth"],
  ["money", "future"],
  ["romantic", "self_worth"],
  ["romantic", "grief_loss"],
  ["romantic", "friends_social"],
  ["family", "grief_loss"],
  ["family", "identity"],
  ["friends_social", "self_worth"],
  ["health", "self_worth"],
  ["health", "future"],
  ["health", "grief_loss"],
  ["identity", "self_worth"],
  ["identity", "future"],
]);

/** Moods that sit next to each other. Hope is the relief side of the hard ones. */
export const EMOTION_ADJACENCY: ReadonlyMap<Emotion, ReadonlySet<Emotion>> = symmetricPairs<Emotion>([
  ["fear", "overwhelm"],
  ["sadness", "loneliness"],
  ["sadness", "numbness"],
  ["loneliness", "numbness"],
  ["anger", "envy"],
  ["shame", "sadness"],
  ["envy", "shame"],
  ["hope", "fear"],
  ["hope", "sadness"],
  ["hope", "loneliness"],
]);

function strongestKey<T>(shares: ReadonlyMap<T, number>): T | null {
  let best: { key: T; share: number } | null = null;
  for (const [key, share] of shares) {
    if (!best || share > best.share) {
      best = { key, share };
    }
  }
  return best?.key ?? null;
}

/**
 * Where a card sits relative to this viewer's themes. `explore` when there are no
 * themes to be near, so a cold viewer is all-explore and the quota has nothing to do.
 */
export function classifyTheme(
  card: { category: Category; emotions: readonly Emotion[] },
  affinity: ViewerAffinity,
): ThemeBucket {
  if (affinity.categories.size === 0 && affinity.emotions.size === 0) {
    return "explore";
  }
  if (affinity.categories.has(card.category)) {
    return "core";
  }
  for (const theme of affinity.categories.keys()) {
    if (CATEGORY_ADJACENCY.get(theme)?.has(card.category)) {
      return "adjacent";
    }
  }
  if (card.emotions.some((emotion) => affinity.emotions.has(emotion))) {
    return "adjacent";
  }
  const topMood = strongestKey(affinity.emotions);
  const dominant = card.emotions[0];
  if (topMood && dominant && EMOTION_ADJACENCY.get(topMood)?.has(dominant)) {
    return "adjacent";
  }
  return "explore";
}

/**
 * The quota for this viewer's pages, or null while there is too little history. Core
 * and adjacent shrink with confidence and explore takes up the slack, so one card
 * nudges a page and five confirm it.
 */
export function themeMix(confidence: number): ThemeMix | null {
  if (!Number.isFinite(confidence) || confidence < MIN_MIX_CONFIDENCE) {
    return null;
  }
  const clamped = Math.min(1, confidence);
  const core = THEME_MIX.core * clamped;
  const adjacent = THEME_MIX.adjacent * clamped;
  return { core, adjacent, explore: 1 - core - adjacent };
}

/**
 * The most a page may hold of each bucket: its share of the page, rounded up. Rank order
 * still decides which card comes next; the caps only stop a bucket from taking more than
 * its share. Their sum is at least the page size, so the caps never leave a page short.
 */
export function bucketCaps(mix: ThemeMix, pageSize: number): Record<ThemeBucket, number> {
  const cap = (share: number): number => Math.ceil(share * pageSize - 1e-9);
  return { core: cap(mix.core), adjacent: cap(mix.adjacent), explore: cap(mix.explore) };
}

export const SPREAD_LIMITS = {
  /** Cards one author can hold in a page. */
  perAuthor: 2,
  /** Consecutive cards allowed to share a life area, a dominant mood, or a cover angle. */
  run: 2,
  /** Cards at the top intensity, so a page is never a wall of crisis. */
  peakIntensity: 6,
  /** Share of a page that may be returning cards. Never broken. */
  returningShare: 0.2,
} as const;

/** Intensity from which a card counts as heavy for pacing. */
export const HEAVY_INTENSITY = 4;

/**
 * How follows shape a page. Following someone is a boost, not a filter: once the
 * viewer follows enough people who post, a quarter of each page is theirs, spread through
 * the page, and never more than half.
 */
export const FOLLOW_MIX = {
  /** Followed authors with a recent post before the floor applies. */
  minAuthors: 3,
  /** Share of a page held for followed authors' recent posts, paced from the top. */
  share: 0.25,
  /** Most of a page followed authors may hold while anything else is left. */
  maxShare: 0.5,
  /** Only a post this young counts toward the floor; an old one is not why you follow someone. */
  recentDays: 7,
} as const;

export type FollowMix = { share: number; maxShare: number; recentSince: Date };

export type SpreadableCard = {
  id: string;
  authorId: string;
  category: Category;
  emotions: readonly Emotion[];
  intensity: number;
  spotlightStyle: Style;
  /** About real harm (solemn) or intense. Two never sit side by side when another order exists. */
  heavy: boolean;
  /** Set when the page follows a theme mix. Absent reads as `explore`. */
  bucket?: ThemeBucket;
  /** Written by someone the viewer follows. */
  followed?: boolean;
  /** Passed once and back. Capped at `SPREAD_LIMITS.returningShare` of a page. */
  returning?: boolean;
  createdAt?: Date;
};

/**
 * The follow floor for this viewer, or null while they follow too few people who post.
 * Counted over the whole candidate set, so every page of a visit uses the same rule.
 */
export function followMix(
  cards: readonly Pick<SpreadableCard, "authorId" | "followed" | "createdAt">[],
  now: Date,
): FollowMix | null {
  const recentSince = new Date(now.getTime() - FOLLOW_MIX.recentDays * 86_400_000);
  const authors = new Set<string>();
  for (const card of cards) {
    if (card.followed && card.createdAt && card.createdAt >= recentSince) {
      authors.add(card.authorId);
    }
  }
  if (authors.size < FOLLOW_MIX.minAuthors) {
    return null;
  }
  return { share: FOLLOW_MIX.share, maxShare: FOLLOW_MIX.maxShare, recentSince };
}

type Run<T> = { key: T | null; length: number };

type SpreadState = {
  perAuthor: Map<string, number>;
  followed: number;
  followedRecent: number;
  returning: number;
  lastAuthor: string | null;
  lastHeavy: boolean;
  peakIntensity: number;
  category: Run<Category>;
  mood: Run<Emotion>;
  spotlight: Run<Style>;
};

function dominantMood(card: SpreadableCard): Emotion | null {
  return card.emotions[0] ?? null;
}

function runIsFull<T>(run: Run<T>, key: T | null, limit: number = SPREAD_LIMITS.run): boolean {
  return key !== null && run.key === key && run.length >= limit;
}

function extendRun<T>(run: Run<T>, key: T | null): Run<T> {
  return run.key === key && key !== null ? { key, length: run.length + 1 } : { key, length: 1 };
}

/**
 * How badly a card fits where it would land. The author cap, the intensity cap, and two
 * heavy cards in a row are real limits: one voice dominating, a wall of crisis, or grief
 * after grief on a stack read one card at a time. A run is only reading rhythm, so
 * breaking one is better than breaking a limit. `never` is the returning cap.
 */
type SpreadFit = "ok" | "soft" | "hard" | "never";

function spreadFit(
  card: SpreadableCard,
  state: SpreadState,
  returningCap: number,
): SpreadFit {
  if (card.returning && state.returning >= returningCap) {
    return "never";
  }
  if ((state.perAuthor.get(card.authorId) ?? 0) >= SPREAD_LIMITS.perAuthor) {
    return "hard";
  }
  if (card.intensity >= 5 && state.peakIntensity >= SPREAD_LIMITS.peakIntensity) {
    return "hard";
  }
  if (card.heavy && state.lastHeavy) {
    return "hard";
  }
  const breaksRun =
    card.authorId === state.lastAuthor ||
    runIsFull(state.category, card.category) ||
    runIsFull(state.mood, dominantMood(card)) ||
    runIsFull(state.spotlight, card.spotlightStyle);
  return breaksRun ? "soft" : "ok";
}

function isRecentFollowed(card: SpreadableCard, follow: FollowMix | null | undefined): boolean {
  return Boolean(follow && card.followed && card.createdAt && card.createdAt >= follow.recentSince);
}

function recordSpread(card: SpreadableCard, state: SpreadState, follow: FollowMix | null | undefined): void {
  state.perAuthor.set(card.authorId, (state.perAuthor.get(card.authorId) ?? 0) + 1);
  if (card.followed) {
    state.followed += 1;
  }
  if (isRecentFollowed(card, follow)) {
    state.followedRecent += 1;
  }
  if (card.returning) {
    state.returning += 1;
  }
  state.lastAuthor = card.authorId;
  state.lastHeavy = card.heavy;
  if (card.intensity >= 5) {
    state.peakIntensity += 1;
  }
  state.category = extendRun(state.category, card.category);
  state.mood = extendRun(state.mood, dominantMood(card));
  state.spotlight = extendRun(state.spotlight, card.spotlightStyle);
}

function emptySpreadState(lastHeavy = false): SpreadState {
  return {
    perAuthor: new Map(),
    followed: 0,
    followedRecent: 0,
    returning: 0,
    lastAuthor: null,
    lastHeavy,
    peakIntensity: 0,
    category: { key: null, length: 0 },
    mood: { key: null, length: 0 },
    spotlight: { key: null, length: 0 },
  };
}

export type SpreadOptions = {
  mix?: ThemeMix | null;
  follow?: FollowMix | null;
  /** The card just before this page was heavy, so pacing carries across the page edge. */
  afterHeavy?: boolean;
};

/** Returning cards one page may hold. At least one, so a small stack can still use them. */
export function returningCap(pageSize: number): number {
  return Math.max(1, Math.floor(SPREAD_LIMITS.returningShare * pageSize));
}

/**
 * Greedy re-pick over one page: take the best-ranked card that does not break a limit.
 * Ranking decides what deserves to be read; this only decides what it is like to read in
 * a row. In order:
 *
 * 1. When the follow floor is behind (fewer than `share` of the slots so far), the best
 *    recent card from someone the viewer follows, if one fits without breaking a limit.
 * 2. The best-ranked card that fits and whose theme bucket (and the followed share) has
 *    room; then one that only breaks a rhythm rule; then the same ignoring that room.
 * 3. When every card left breaks a limit (a small community), the card whose author has
 *    the fewest cards on the page, ties to rank. Never plain rank order.
 * 4. Only returning cards over their cap are left: the page ends short.
 */
export function spreadPage<T extends SpreadableCard>(
  ranked: readonly T[],
  pageSize: number,
  options: SpreadOptions = {},
): T[] {
  const state = emptySpreadState(options.afterHeavy ?? false);
  const remaining = [...ranked];
  const page: T[] = [];
  const placed: Record<ThemeBucket, number> = { core: 0, adjacent: 0, explore: 0 };
  const caps = options.mix ? bucketCaps(options.mix, pageSize) : null;
  const follow = options.follow ?? null;
  const followCap = follow ? Math.ceil(follow.maxShare * pageSize - 1e-9) : Number.POSITIVE_INFINITY;
  const returning = returningCap(pageSize);

  const hasRoom = (card: T): boolean => {
    if (card.followed && state.followed >= followCap) {
      return false;
    }
    if (!caps) {
      return true;
    }
    const bucket = card.bucket ?? "explore";
    return placed[bucket] < caps[bucket];
  };

  while (page.length < pageSize && remaining.length > 0) {
    const fits = remaining.map((card) => spreadFit(card, state, returning));
    const pick = (level: SpreadFit, respectCaps: boolean, only?: (card: T) => boolean): number =>
      remaining.findIndex(
        (card, position) =>
          fits[position] === level && (!only || only(card)) && (!respectCaps || hasRoom(card)),
      );

    let index = -1;
    if (follow && state.followedRecent < Math.floor(follow.share * (page.length + 1))) {
      const eligible = (card: T): boolean => isRecentFollowed(card, follow);
      index = pick("ok", true, eligible);
      if (index === -1) {
        index = pick("soft", true, eligible);
      }
    }
    // Spending light cards early would leave heavy ones with nothing between them, so
    // once heavy outnumber light, a heavy card goes next whenever one may.
    if (index === -1 && !state.lastHeavy) {
      const heavyLeft = remaining.filter((card) => card.heavy).length;
      if (heavyLeft > remaining.length - heavyLeft) {
        const heavy = (card: T): boolean => card.heavy;
        index = pick("ok", true, heavy);
        if (index === -1) {
          index = pick("soft", true, heavy);
        }
      }
    }
    if (index === -1) {
      index = pick("ok", true);
    }
    if (index === -1) {
      index = pick("soft", true);
    }
    if (index === -1) {
      index = pick("ok", false);
    }
    if (index === -1) {
      index = pick("soft", false);
    }
    if (index === -1) {
      let fewest = Number.POSITIVE_INFINITY;
      for (const [position, card] of remaining.entries()) {
        if (fits[position] !== "hard") {
          continue;
        }
        const count = state.perAuthor.get(card.authorId) ?? 0;
        if (count < fewest) {
          fewest = count;
          index = position;
        }
      }
    }
    if (index === -1) {
      break;
    }
    const [card] = remaining.splice(index, 1);
    if (!card) {
      break;
    }
    recordSpread(card, state, follow);
    placed[card.bucket ?? "explore"] += 1;
    page.push(card);
  }

  return page;
}

/**
 * The whole ranked list, spread one page at a time. The limits are per page, but the
 * result has to be one stable global order or offset paging would drop and repeat
 * cards as the offset moves — so the windows are computed the same way every request.
 * Pacing carries across the page edge: a page never opens heavy after a heavy card.
 */
export function spreadRanked<T extends SpreadableCard>(
  ranked: readonly T[],
  pageSize: number,
  options: SpreadOptions = {},
): T[] {
  const spread: T[] = [];
  let remaining: readonly T[] = ranked;
  let afterHeavy = options.afterHeavy ?? false;
  while (remaining.length > 0) {
    const window = spreadPage(remaining, pageSize, { ...options, afterHeavy });
    if (window.length === 0) {
      break;
    }
    spread.push(...window);
    afterHeavy = window[window.length - 1]?.heavy ?? false;
    const taken = new Set(window.map((card) => card.id));
    remaining = remaining.filter((card) => !taken.has(card.id));
  }
  return spread;
}

/**
 * Share of a viewer's cards that open on the angle they save on most. Deliberately not
 * all of them: the mix of voices is the point, and one style on every card would make
 * the stack read like a single voice.
 */
const PREFERRED_COVER_SHARE = 0.5;

/**
 * Which angle a stack card opens on for this viewer.
 *
 * A returning card opens on the first angle, in the card's own order, the viewer has not
 * seen: that is the whole reason it came back. Otherwise someone who keeps saving on
 * Witty meets Witty more often, as a stable coin flip per card rather than a takeover.
 * Deterministic in the card and the viewer, so a card does not change face on a reload.
 */
export function openingStyle(options: {
  cardId: string;
  viewerId: string;
  cover: Style;
  /** The card's angles in the order the cook ranked them. */
  available: readonly Style[];
  preferred: Style | null;
  checked?: ReadonlySet<Style>;
}): Style {
  const { checked, preferred, available } = options;
  if (checked && checked.size > 0) {
    const unseen = available.find((style) => !checked.has(style));
    if (unseen) {
      return unseen;
    }
  }
  if (preferred && preferred !== options.cover && available.includes(preferred)) {
    return jitterTerm(options.cardId, options.viewerId) < PREFERRED_COVER_SHARE
      ? preferred
      : options.cover;
  }
  return options.cover;
}

/**
 * One visit to the stack. The seed varies the jitter between visits; `startedAt` freezes
 * every ranking input, so the cards left keep their order however many get decided.
 */
export type FeedSession = {
  seed: string;
  startedAt: Date;
};

/**
 * `seed|startedAt`, base64url. Opaque on purpose: the client only echoes it back, so the
 * shape stays free to change without another App Store release.
 */
export function encodeFeedSession(session: FeedSession): string {
  const raw = `${session.seed}|${session.startedAt.toISOString()}`;
  return Buffer.from(raw, "utf8").toString("base64url");
}

export function decodeFeedSession(raw: string): FeedSession | null {
  let decoded: string;
  try {
    decoded = Buffer.from(raw, "base64url").toString("utf8");
  } catch {
    return null;
  }
  const parts = decoded.split("|");
  const [seed, startedAt] = parts;
  if (parts.length !== 2 || !seed || !startedAt) {
    return null;
  }
  if (!/^[A-Za-z0-9_-]{8,64}$/.test(seed)) {
    return null;
  }
  const started = new Date(startedAt);
  if (Number.isNaN(started.getTime())) {
    return null;
  }
  return { seed, startedAt: started };
}

/** Ranking is opt-in per deployment, so a bad order is one variable away from newest-first. */
export function rankingEnabled(environment: NodeJS.ProcessEnv = process.env): boolean {
  return environment.FEED_RANKING?.trim().toLowerCase() === "resonance";
}
