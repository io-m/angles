import { createHash } from "node:crypto";
import { type Category, type Emotion, type Style } from "../types/index.js";

/**
 * Resonance ranking for the Home stack.
 *
 * What it optimizes, in order: recency (a newer post beats an older one unless its save
 * rate or themes clearly say otherwise), recognition (thoughts near the themes this viewer
 * writes and saves, held to a core/adjacent/explore page mix so it never becomes an echo),
 * relief (cards the people who met them kept), a different order every visit, and a fair
 * first hearing for posts too few people have decided on yet.
 *
 * What it refuses to optimize: dwell time, session length, and distress. Intensity is
 * capped and paced by the spread pass, never rewarded. A card's save rate is only ever
 * compared with cards of its own weight: heavy cards are passed more, and they must not
 * lose to light ones for it.
 */
export const RANKING_WEIGHTS = {
  freshness: 2.0,
  /** Save rate among the people who decided, shrunk toward its stratum and relative to it. */
  quality: 0.6,
  /** Distinct people who saved it, damped and capped: reach a rate cannot show. */
  reach: 0.2,
  affinity: 0.7,
  followed: 0.6,
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
  maxTags: 8,
  minTagShare: 0.05,
} as const;

/**
 * Freshness, two decays added. Most of it (`fast`) is one day: a post from this morning is
 * worth most of a new one, yesterday's about a third. The rest (`slow`) fades over two
 * weeks, so a card people keep can still come back after a few days instead of time
 * flattening every older post to zero.
 */
const FRESHNESS = { fastHours: 36, slowHours: 24 * 14, slowShare: 0.15 } as const;

/** Saves where reach saturates, so one popular card cannot own the stack. */
const REACH_SATURATION = 10;

/**
 * Save-rate quality. `prior` is how many decisions' worth of the stratum's own rate every
 * card starts with, so one save from two people does not beat eight from forty. `lift` is
 * the rate over its stratum's where the term reaches ±1.
 */
export const QUALITY_CONFIG = {
  prior: 10,
  liftRange: 1,
  /** The stratum rate before there are enough decisions to measure one. */
  defaultBaseline: 0.3,
  /** Decisions' worth of `defaultBaseline` a measured stratum rate starts from. */
  baselinePrior: 30,
} as const;

/**
 * A card with fewer decisions than this has not been judged yet. A share of every page
 * goes to those, paced from the top, whatever their age, so a post is never buried before
 * enough people have met it.
 */
export const EXPLORATION = { maxDecisions: 8, share: 0.2 } as const;

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
  /** Distinct other people who saved or passed it. Absent reads as `saves`. */
  decisions?: number;
  /** Heavy cards are judged against heavy cards only. */
  heavy?: boolean;
  tags?: readonly string[];
  followed: boolean;
  /** Passed once by this viewer and back on an angle they never saw. */
  returning?: boolean;
};

/** The save rate of each stratum: what an average card of that weight gets. */
export type QualityBaselines = { heavy: number; light: number };

export const DEFAULT_BASELINES: QualityBaselines = {
  heavy: QUALITY_CONFIG.defaultBaseline,
  light: QUALITY_CONFIG.defaultBaseline,
};

/**
 * Each stratum's rate over the candidates, pulled toward the default until there are
 * enough decisions, and kept off 0 and 1 so a lift is always defined.
 */
export function qualityBaselines(
  cards: readonly { heavy: boolean; saves: number; decisions: number }[],
): QualityBaselines {
  const rate = (heavy: boolean): number => {
    let saves = 0;
    let decisions = 0;
    for (const card of cards) {
      if (card.heavy === heavy) {
        saves += card.saves;
        decisions += Math.max(card.decisions, card.saves);
      }
    }
    const prior = QUALITY_CONFIG.baselinePrior;
    const shrunk = (saves + prior * QUALITY_CONFIG.defaultBaseline) / (decisions + prior);
    return Math.min(0.95, Math.max(0.05, shrunk));
  };
  return { heavy: rate(true), light: rate(false) };
}

/**
 * The life areas and moods a viewer is mostly in, as shares of their recent activity.
 * The maps hold only the themes (top few above a minimum share), never the long tail.
 * `confidence` is how much evidence backs them: one card is a hint, not a profile.
 */
export type ViewerAffinity = {
  categories: ReadonlyMap<Category, number>;
  emotions: ReadonlyMap<Emotion, number>;
  /** Tag slugs, a finer and weaker hint than life area and mood. Absent reads as none. */
  tags?: ReadonlyMap<string, number>;
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
  tags?: readonly string[];
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
  const tagWeights = new Map<string, number>();
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
    for (const tag of new Set(signal.tags ?? [])) {
      tagWeights.set(tag, (tagWeights.get(tag) ?? 0) + weight);
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
  const affinity: ViewerAffinity = {
    categories,
    emotions,
    confidence: Math.min(1, total / AFFINITY_CONFIG.fullConfidenceWeight),
  };
  const tags = topShares(floored(tagWeights), AFFINITY_CONFIG.maxTags, AFFINITY_CONFIG.minTagShare);
  if (tags.size > 0) {
    affinity.tags = tags;
  }
  return affinity;
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
  quality: number;
  reach: number;
  affinity: number;
  followed: number;
  jitter: number;
  returning: number;
};

export type ScoredCard = { id: string; score: number; terms: RankingTerms };

export function freshnessTerm(card: RankableCard, now: Date): number {
  const ageHours = Math.max(0, (now.getTime() - card.createdAt.getTime()) / 3_600_000);
  return (
    (1 - FRESHNESS.slowShare) * Math.exp(-ageHours / FRESHNESS.fastHours) +
    FRESHNESS.slowShare * Math.exp(-ageHours / FRESHNESS.slowHours)
  );
}

/**
 * The card's save rate among the people who decided on it, shrunk toward its stratum's
 * rate and read relative to it: 0 is an ordinary card of its weight (and every card nobody
 * has decided on yet), +1 clearly kept more, −1 clearly kept less. A heavy card is only
 * ever measured against heavy cards, so being passed the way grief is passed costs nothing.
 */
export function qualityTerm(card: RankableCard, baselines: QualityBaselines = DEFAULT_BASELINES): number {
  const baseline = card.heavy ? baselines.heavy : baselines.light;
  const saves = Math.max(0, card.saves);
  const decisions = Math.max(saves, card.decisions ?? saves);
  const prior = QUALITY_CONFIG.prior;
  const rate = (saves + prior * baseline) / (decisions + prior);
  const lift = rate / baseline - 1;
  return Math.max(-1, Math.min(1, lift / QUALITY_CONFIG.liftRange));
}

/** Distinct people who saved the card, damped and capped. */
export function reachTerm(card: RankableCard): number {
  if (card.saves <= 0) {
    return 0;
  }
  const scaled = Math.log1p(card.saves) / Math.log1p(REACH_SATURATION);
  return Math.min(1, scaled);
}

/**
 * How close a card sits to the viewer's themes, graded by how strong each theme is.
 * A life area is worth more than a mood, and a mood more than a tag. Tags only take a
 * share once the viewer has some. The viewer's confidence is applied by the caller.
 */
export function affinityTerm(card: RankableCard, affinity: ViewerAffinity): number {
  const category = relativeShare(affinity.categories, card.category);
  let mood = 0;
  for (const emotion of new Set(card.emotions)) {
    mood += relativeShare(affinity.emotions, emotion);
  }
  const moodScore = Math.min(1, mood / 2);
  const tagShares = affinity.tags;
  if (!tagShares || tagShares.size === 0) {
    return 0.6 * category + 0.4 * moodScore;
  }
  let tag = 0;
  for (const slug of new Set(card.tags ?? [])) {
    tag += relativeShare(tagShares, slug);
  }
  return 0.5 * category + 0.35 * moodScore + 0.15 * Math.min(1, tag / 2);
}

/**
 * The variety knob: stable for a visit, different on the next. Deterministic so paging
 * cannot shuffle under the reader — `ORDER BY random()` would make offsets meaningless.
 */
export function jitterTerm(cardId: string, seed: string): number {
  const digest = createHash("sha256").update(`${seed}:${cardId}`).digest();
  return digest.readUInt32BE(0) / 0x1_0000_0000;
}

export type ScoreOptions = {
  now: Date;
  seed: string;
  affinity?: ViewerAffinity;
  baselines?: QualityBaselines;
};

export function scoreCard(card: RankableCard, options: ScoreOptions): ScoredCard {
  const affinity = options.affinity ?? EMPTY_AFFINITY;
  const terms: RankingTerms = {
    freshness: freshnessTerm(card, options.now),
    quality: qualityTerm(card, options.baselines),
    reach: reachTerm(card),
    affinity: affinityTerm(card, affinity) * affinity.confidence,
    followed: card.followed ? 1 : 0,
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

export function rankCards(cards: readonly RankableCard[], options: ScoreOptions): ScoredCard[] {
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
  /**
   * Share of a whole visit one author may hold, never below `perAuthor`. Without it the
   * most active author holds two of every twelve cards from the first page to the last.
   */
  visitAuthorShare: 0.1,
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
  /** Too few people have decided on it to judge it yet (`EXPLORATION`). */
  exploring?: boolean;
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
  exploring: number;
  lastAuthor: string | null;
  lastHeavy: boolean;
  peakIntensity: number;
  category: Run<Category>;
  mood: Run<Emotion>;
  spotlight: Run<Style>;
  visit: VisitSpread | null;
  /** The visit's count before this page, so the visit cap grows with each slot. */
  visitPlacedBefore: number;
};

/**
 * What one page hands the next inside a visit: every author's count so far and the
 * reading rhythm at the edge, so a run or a heavy card does not restart at each page.
 */
export type VisitSpread = {
  authorTotals: Map<string, number>;
  placed: number;
  lastAuthor: string | null;
  lastHeavy: boolean;
  category: Run<Category>;
  mood: Run<Emotion>;
  spotlight: Run<Style>;
};

export function emptyVisitSpread(lastHeavy = false): VisitSpread {
  return {
    authorTotals: new Map(),
    placed: 0,
    lastAuthor: null,
    lastHeavy,
    category: { key: null, length: 0 },
    mood: { key: null, length: 0 },
    spotlight: { key: null, length: 0 },
  };
}

/** The author's cards in the visit so far, this page included. */
function visitAuthorCount(state: SpreadState, authorId: string): number {
  return (state.visit?.authorTotals.get(authorId) ?? 0) + (state.perAuthor.get(authorId) ?? 0);
}

function visitAuthorCap(state: SpreadState, pageLength: number): number {
  const slots = state.visitPlacedBefore + pageLength + 1;
  return Math.max(SPREAD_LIMITS.perAuthor, Math.ceil(SPREAD_LIMITS.visitAuthorShare * slots - 1e-9));
}

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
  pageLength: number,
): SpreadFit {
  if (card.returning && state.returning >= returningCap) {
    return "never";
  }
  if ((state.perAuthor.get(card.authorId) ?? 0) >= SPREAD_LIMITS.perAuthor) {
    return "hard";
  }
  if (state.visit && visitAuthorCount(state, card.authorId) >= visitAuthorCap(state, pageLength)) {
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
  if (card.exploring) {
    state.exploring += 1;
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

function emptySpreadState(lastHeavy: boolean, visit: VisitSpread | null): SpreadState {
  return {
    perAuthor: new Map(),
    followed: 0,
    followedRecent: 0,
    returning: 0,
    exploring: 0,
    lastAuthor: visit?.lastAuthor ?? null,
    lastHeavy: visit ? visit.lastHeavy : lastHeavy,
    peakIntensity: 0,
    category: visit ? { ...visit.category } : { key: null, length: 0 },
    mood: visit ? { ...visit.mood } : { key: null, length: 0 },
    spotlight: visit ? { ...visit.spotlight } : { key: null, length: 0 },
    visit,
    visitPlacedBefore: visit?.placed ?? 0,
  };
}

function carryIntoVisit(state: SpreadState, page: readonly SpreadableCard[]): void {
  const visit = state.visit;
  if (!visit) {
    return;
  }
  for (const card of page) {
    visit.authorTotals.set(card.authorId, (visit.authorTotals.get(card.authorId) ?? 0) + 1);
  }
  visit.placed += page.length;
  visit.lastAuthor = state.lastAuthor;
  visit.lastHeavy = state.lastHeavy;
  visit.category = state.category;
  visit.mood = state.mood;
  visit.spotlight = state.spotlight;
}

export type SpreadOptions = {
  mix?: ThemeMix | null;
  follow?: FollowMix | null;
  /** Share of each page held for cards still `exploring`. Absent or null: no floor. */
  exploreShare?: number | null;
  /** The card just before this page was heavy, so pacing carries across the page edge. */
  afterHeavy?: boolean;
  /**
   * The visit so far. Given, the author cap and the reading rhythm span the whole visit
   * (it wins over `afterHeavy`), and this page's cards are added to it.
   */
  visit?: VisitSpread;
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
 * 1. When a floor is behind (fewer than its share of the slots so far), the best card it
 *    is for, if one fits without breaking a limit. In order: recent cards from people the
 *    viewer follows, cards still exploring, then cards outside the viewer's themes.
 * 2. The best-ranked card that fits and whose theme bucket (and the followed share) has
 *    room; then one that only breaks a rhythm rule; then the same ignoring that room.
 * 3. When every card left breaks a limit (a small community), the card whose author has
 *    the fewest cards so far, ties to rank. Never plain rank order.
 * 4. Only returning cards over their cap are left: the page ends short.
 */
export function spreadPage<T extends SpreadableCard>(
  ranked: readonly T[],
  pageSize: number,
  options: SpreadOptions = {},
): T[] {
  const state = emptySpreadState(options.afterHeavy ?? false, options.visit ?? null);
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

  const exploreShare = options.exploreShare ?? 0;
  const exploreBucketShare = options.mix?.explore ?? 0;

  while (page.length < pageSize && remaining.length > 0) {
    const fits = remaining.map((card) => spreadFit(card, state, returning, page.length));
    const pick = (level: SpreadFit, respectCaps: boolean, only?: (card: T) => boolean): number =>
      remaining.findIndex(
        (card, position) =>
          fits[position] === level && (!only || only(card)) && (!respectCaps || hasRoom(card)),
      );
    const pickFor = (only: (card: T) => boolean): number => {
      const found = pick("ok", true, only);
      return found === -1 ? pick("soft", true, only) : found;
    };
    const behind = (count: number, share: number): boolean =>
      share > 0 && count < Math.floor(share * (page.length + 1));

    let index = -1;
    if (follow && behind(state.followedRecent, follow.share)) {
      index = pickFor((card) => isRecentFollowed(card, follow));
    }
    if (index === -1 && behind(state.exploring, exploreShare)) {
      index = pickFor((card) => card.exploring === true);
    }
    if (index === -1 && behind(placed.explore, exploreBucketShare)) {
      index = pickFor((card) => (card.bucket ?? "explore") === "explore");
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
        const count = visitAuthorCount(state, card.authorId);
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

  carryIntoVisit(state, page);
  return page;
}

/**
 * The whole ranked list, spread one page at a time into one stable visit order. Page
 * limits (author, intensity, returning, the mixes) apply per window; the visit author cap,
 * reading rhythm, and heavy pacing carry from each window into the next, so the most
 * active author does not reset to two at every page edge.
 */
export function spreadRanked<T extends SpreadableCard>(
  ranked: readonly T[],
  pageSize: number,
  options: SpreadOptions = {},
): T[] {
  const spread: T[] = [];
  const visit = options.visit ?? emptyVisitSpread(options.afterHeavy ?? false);
  let remaining: readonly T[] = ranked;
  while (remaining.length > 0) {
    const window = spreadPage(remaining, pageSize, { ...options, visit });
    if (window.length === 0) {
      break;
    }
    spread.push(...window);
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
