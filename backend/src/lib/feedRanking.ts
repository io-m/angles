import { createHash } from "node:crypto";
import { STYLES, type Category, type Emotion, type Style } from "../types/index.js";

/**
 * Resonance ranking for the community feed.
 *
 * What it optimizes, in order: recency (this is a social feed, so a newer post beats an
 * older one unless hearts or themes clearly say otherwise), recognition (thoughts near
 * the themes this viewer writes and hearts, held to a core/adjacent/explore page mix so
 * it never becomes an echo), relief (angles that demonstrably helped a stranger), a
 * different read on every pull, and exposure for posts nobody has found yet.
 *
 * What it refuses to optimize: dwell time, session length, and distress. Intensity is
 * capped by the spread pass, never rewarded — that is the doom-scroll lever and it
 * stays off. A useful reframe and a closed app is a success.
 */
export const RANKING_WEIGHTS = {
  freshness: 2.0,
  resonance: 0.8,
  affinity: 0.7,
  followed: 0.6,
  secondChance: 0.25,
  jitter: 0.15,
  /**
   * A card the viewer already hearted some angles of, but not all. It stays on For you
   * (opening on an angle they have not kept) and drops by about half a day of freshness.
   */
  partlyKept: -0.5,
} as const;

/**
 * Extra terms for a style shelf. Resonance is capped like the card-level term, and
 * the cover is only a nudge: the author chose it, which is not evidence it helped.
 */
export const STYLE_RANKING_WEIGHTS = {
  styleResonance: 0.55,
  cover: 0.05,
  /**
   * Subtracted on a style shelf from a card whose primary tab, for this viewer, is a
   * different style, once the card is old enough to have settled (see `OFF_TAB_FADE_HOURS`).
   * Larger than everything an old card can score on the terms every tab shares (resonance,
   * follow, theme, second chance, jitter come to 2.5), so an off-tab card ranks
   * below all of the tab's own cards even when it is popular: those hearts are about the
   * thought, not this voice. Angle hearts on this tab make it the primary tab instead. A penalty and not a filter: a thin community still
   * fills the tab once its primary cards run out, and a strong card can lead a second tab.
   */
  offTab: 2.75,
} as const;

/**
 * The off-tab penalty fades in with the post's age: none under `start` hours, full from
 * `full` hours. A social feed shows what was just posted, so a brand-new card appears on
 * every tab first and only then settles onto the tab it fits best.
 */
export const OFF_TAB_FADE_HOURS = { start: 1, full: 6 } as const;

export function offTabFade(card: { createdAt: Date }, now: Date): number {
  const ageHours = Math.max(0, (now.getTime() - card.createdAt.getTime()) / 3_600_000);
  const span = OFF_TAB_FADE_HOURS.full - OFF_TAB_FADE_HOURS.start;
  return Math.min(1, Math.max(0, (ageHours - OFF_TAB_FADE_HOURS.start) / span));
}

/**
 * Weight of the stable viewer-and-card hash when choosing a card's primary tab. It only
 * decides when the fits are close, which for a viewer with no hearts is every card.
 */
export const PRIMARY_TIE_WEIGHT = 0.1;

/** How a viewer's themes are learned. Hearts outweigh writing: choosing to keep a
 * reframe says more about what someone reads than what they happened to write. */
export const AFFINITY_CONFIG = {
  halfLifeDays: 14,
  /** Old taste fades but never vanishes, so a returning viewer is not treated as new. */
  decayFloor: 0.1,
  authoredWeight: 1,
  heartWeight: 1.5,
  /** Decayed signal weight at which the themes are fully trusted. */
  fullConfidenceWeight: 5,
  maxCategories: 3,
  minCategoryShare: 0.15,
  maxEmotions: 5,
  minEmotionShare: 0.1,
} as const;

/** Hearts on this style before its affinity fully replaces the viewer's general taste. */
export const STYLE_AFFINITY_FULL_HEARTS = 5;

/**
 * Freshness decay scale in hours. One day: a post from this morning is worth most of a
 * new one, yesterday's about a third, and after three days time no longer separates
 * posts, which leaves hearts, themes and follows to order them. With weight 2.0 a post
 * from two hours ago outscores a day-old one by about 1.1, more than a lone heart.
 */
const FRESHNESS_SCALE_HOURS = 24;

/** Hearts where resonance saturates, so one popular card cannot own the feed. */
const RESONANCE_SATURATION = 10;

/** A post gets a leg up while it is this young and still unhearted. */
const SECOND_CHANCE_DAYS = { start: 1, full: 14, end: 30 } as const;

export type RankableCard = {
  id: string;
  authorId: string;
  createdAt: Date;
  category: Category;
  emotions: readonly Emotion[];
  /** Distinct other people who hearted it. The viewer's own hearts never count. */
  hearts: number;
  followed: boolean;
  /** The viewer's own card: no theme match and no follow, so it competes as a stranger's would. */
  own?: boolean;
  /** The viewer hearted some of this card's angles but not all of them. For you only. */
  partlyKept?: boolean;
  /** Hearts on one angle. Read only while ranking that style shelf. */
  angleHearts?: number;
  /** Hearts on each angle. Read only to choose the card's primary tab. */
  angleHeartsByStyle?: Partial<Record<Style, number>>;
  /** The angles this card actually has. Absent means all four. */
  availableStyles?: readonly Style[];
  /** The cover the author saved. A weak shelf signal, never a For you input. */
  coverStyle?: Style;
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

/** One thing a viewer wrote or hearted, reduced to what theme learning needs. */
export type AffinitySignal = {
  category: Category;
  emotions: readonly Emotion[];
  at: Date;
  source: "authored" | "hearted";
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
  const ordered = [...weights.entries()].sort(
    (left, right) => right[1] - left[1] || (left[0] < right[0] ? -1 : 1),
  );
  for (const [key, weight] of ordered.slice(0, keep)) {
    const share = weight / sum;
    // A flat profile still has a leader, so the top entry always survives.
    if (shares.size === 0 || share >= minShare) {
      shares.set(key, share);
    }
  }
  return shares;
}

/**
 * Themes from recent activity. Each signal decays with a 14-day half-life (floored, so
 * old taste fades without vanishing), hearts count more than writing, and `other` is
 * never a theme: it is where nothing fit, so matching it means nothing.
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
    const weight =
      (signal.source === "hearted" ? AFFINITY_CONFIG.heartWeight : AFFINITY_CONFIG.authoredWeight) *
      decay;
    total += weight;
    if (signal.category !== "other") {
      categoryWeights.set(signal.category, (categoryWeights.get(signal.category) ?? 0) + weight);
    }
    for (const emotion of new Set(signal.emotions)) {
      emotionWeights.set(emotion, (emotionWeights.get(emotion) ?? 0) + weight);
    }
  }

  const categories = topShares(
    categoryWeights,
    AFFINITY_CONFIG.maxCategories,
    AFFINITY_CONFIG.minCategoryShare,
  );
  const emotions = topShares(
    emotionWeights,
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
  partlyKept: number;
};

export type ScoredCard = { id: string; score: number; terms: RankingTerms };

export function freshnessTerm(card: RankableCard, now: Date): number {
  const ageHours = Math.max(0, (now.getTime() - card.createdAt.getTime()) / 3_600_000);
  return Math.exp(-ageHours / FRESHNESS_SCALE_HOURS);
}

/** Distinct people who hearted any angle, damped and capped. */
export function resonanceTerm(card: RankableCard): number {
  if (card.hearts <= 0) {
    return 0;
  }
  const scaled = Math.log1p(card.hearts) / Math.log1p(RESONANCE_SATURATION);
  return Math.min(1, scaled);
}

/**
 * How close a card sits to the viewer's themes, graded by how strong each theme is.
 * A life area is worth more than a mood. This is the raw overlap: the viewer's general
 * confidence is applied by the caller, because a style shelf replaces it with hearts.
 */
export function affinityTerm(card: RankableCard, affinity: ViewerAffinity): number {
  const category = relativeShare(affinity.categories, card.category);
  let mood = 0;
  for (const emotion of new Set(card.emotions)) {
    mood += relativeShare(affinity.emotions, emotion);
  }
  return 0.6 * category + 0.4 * Math.min(1, mood / 2);
}

/** 0 with no hearts on this style, 1 once the viewer has hearted it five times. */
export function styleAffinityConfidence(hearts: number): number {
  if (!Number.isFinite(hearts) || hearts <= 0) {
    return 0;
  }
  return Math.min(1, hearts / STYLE_AFFINITY_FULL_HEARTS);
}

/**
 * General taste, replaced by taste learned from this style as evidence accumulates.
 * One heart moves the term a fifth of the way. It cannot take the shelf over.
 */
export function blendedAffinityTerm(
  card: RankableCard,
  general: ViewerAffinity,
  styleAffinity: ViewerAffinity,
  hearts: number,
): number {
  const confidence = styleAffinityConfidence(hearts);
  const base = affinityTerm(card, general) * general.confidence;
  // Gated by how many hearts back it, not by its own confidence: counting both would
  // discount the same evidence twice.
  const specific = affinityTerm(card, styleAffinity);
  return (1 - confidence) * base + confidence * specific;
}

/** A style shelf's extra inputs. Absent on For you, which keeps the base score alone. */
export type StyleShelfContext = {
  style: Style;
  affinity: ViewerAffinity;
  /** How many times this viewer has hearted this style. */
  hearts: number;
  /** Strangers' hearts on this card's copy of that style. */
  angleHearts: number;
  coverMatches: boolean;
  /** This card's primary tab for the viewer is a different style. */
  offTab?: boolean;
};

/** One style tab's taste for a viewer: what they heart on it, and how often. */
export type StyleTabContext = { affinity: ViewerAffinity; hearts: number };

export type StyleTabs = Readonly<Record<Style, StyleTabContext>>;

/**
 * How well one angle of a card suits this viewer, beyond what suits them everywhere.
 * Only the style-specific part of the shelf score: freshness, followed and the rest are
 * the same on every tab, so they cannot decide which tab a card belongs to.
 *
 * - The tab's taste counts relative to the viewer's general taste. Hearts on any tab feed
 *   the general taste, so without the subtraction one tab with hearts would claim every
 *   card that matches the viewer at all and leave the other three empty.
 * - The author's cover is left out on purpose: it is one style for every viewer, so
 *   counting it would send most of a cold catalog to whichever style authors pick. The
 *   shelf score still nudges by cover.
 */
export function styleFitTerm(
  card: RankableCard,
  style: Style,
  general: ViewerAffinity,
  tab: StyleTabContext,
): number {
  const confidence = styleAffinityConfidence(tab.hearts);
  const overall = affinityTerm(card, general) * general.confidence;
  const specific = affinityTerm(card, tab.affinity);
  return (
    RANKING_WEIGHTS.affinity * confidence * (specific - overall) +
    STYLE_RANKING_WEIGHTS.styleResonance *
      resonanceTerm({ ...card, hearts: card.angleHeartsByStyle?.[style] ?? 0 })
  );
}

/**
 * The one tab a card belongs on first, for this viewer: the style it fits best among the
 * angles it has. Ties (every cold-start card) break on a hash of viewer, card and style,
 * with no session seed, so each tab's request reaches the same answer without talking to
 * the others, and a new viewer still gets a roughly even, personal split of the catalog.
 */
export function primaryStyleFor(
  card: RankableCard,
  options: { viewerId: string; general: ViewerAffinity; tabs: StyleTabs },
): Style {
  const available = card.availableStyles?.length ? card.availableStyles : STYLES;
  let best: { style: Style; value: number } | null = null;
  for (const style of STYLES) {
    if (!available.includes(style)) {
      continue;
    }
    const value =
      styleFitTerm(card, style, options.general, options.tabs[style]) +
      PRIMARY_TIE_WEIGHT * jitterTerm(card.id, `${options.viewerId}:primary:${style}`);
    if (!best || value > best.value) {
      best = { style, value };
    }
  }
  return best?.style ?? card.coverStyle ?? STYLES[0];
}

export function assignPrimaryStyles(
  cards: readonly RankableCard[],
  options: { viewerId: string; general: ViewerAffinity; tabs: StyleTabs },
): Map<string, Style> {
  return new Map(cards.map((card) => [card.id, primaryStyleFor(card, options)]));
}

/**
 * Exposure for a post nobody has found yet. In a community this small, an author whose
 * card gets no reads stops posting, so this is fairness rather than quality.
 */
export function secondChanceTerm(card: RankableCard, now: Date): number {
  if (card.hearts > 0) {
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
 * The variety knob: stable for a session, different on the next visit. Deterministic
 * so paging cannot shuffle under a scroll — `ORDER BY random()` would both discard
 * `cards_public_created_idx` and make paging meaningless.
 */
export function jitterTerm(cardId: string, seed: string): number {
  const digest = createHash("sha256").update(`${seed}:${cardId}`).digest();
  return digest.readUInt32BE(0) / 0x1_0000_0000;
}

export function scoreCard(
  card: RankableCard,
  options: { now: Date; seed: string; affinity?: ViewerAffinity; style?: StyleShelfContext },
): ScoredCard {
  const affinity = options.affinity ?? EMPTY_AFFINITY;
  const style = options.style;
  const terms: RankingTerms = {
    freshness: freshnessTerm(card, options.now),
    resonance: resonanceTerm(card),
    // Themes are learned from what the viewer writes, so their own card would always be
    // a perfect match. It gets none, and competes the way a stranger's card would.
    affinity: card.own
      ? 0
      : style
        ? blendedAffinityTerm(card, affinity, style.affinity, style.hearts)
        : affinityTerm(card, affinity) * affinity.confidence,
    followed: card.followed && !card.own ? 1 : 0,
    secondChance: secondChanceTerm(card, options.now),
    // A style salt keeps two shelves from tying into the same order. For you omits it.
    jitter: jitterTerm(card.id, style ? `${options.seed}:${style.style}` : options.seed),
    partlyKept: card.partlyKept && !style ? 1 : 0,
  };

  let score = 0;
  for (const key of Object.keys(RANKING_WEIGHTS) as (keyof RankingTerms)[]) {
    score += RANKING_WEIGHTS[key] * terms[key];
  }
  if (style) {
    score +=
      STYLE_RANKING_WEIGHTS.styleResonance *
      resonanceTerm({ ...card, hearts: style.angleHearts });
    score += STYLE_RANKING_WEIGHTS.cover * (style.coverMatches ? 1 : 0);
    if (style.offTab) {
      score -= STYLE_RANKING_WEIGHTS.offTab * offTabFade(card, options.now);
    }
  }
  return { id: card.id, score, terms };
}

/**
 * Whether the viewer has already kept this card on the shelf they are reading. A heart is
 * on one answer, not the whole card, so For you hides a card only once every angle it has
 * is hearted; until then it can still show an answer they have not kept. A style tab hides
 * it as soon as that tab's own angle is hearted.
 */
export function isKeptOnShelf(
  keptStyles: ReadonlySet<Style> | undefined,
  shelf: Style | undefined,
  available: readonly Style[] = STYLES,
): boolean {
  if (!keptStyles || keptStyles.size === 0) {
    return false;
  }
  if (shelf !== undefined) {
    return keptStyles.has(shelf);
  }
  const angles = available.length > 0 ? available : STYLES;
  return angles.every((style) => keptStyles.has(style));
}

/** Some of the card's angles are hearted and some are not. */
export function isPartlyKept(
  keptStyles: ReadonlySet<Style> | undefined,
  available: readonly Style[] = STYLES,
): boolean {
  if (!keptStyles || keptStyles.size === 0) {
    return false;
  }
  const angles = available.length > 0 ? available : STYLES;
  return angles.some((style) => !keptStyles.has(style)) && angles.some((style) => keptStyles.has(style));
}

/** Highest first, ties broken by id so one seed always produces one order. */
export function compareRanked(left: ScoredCard, right: ScoredCard): number {
  return right.score - left.score || (left.id < right.id ? 1 : -1);
}

export function rankCards(
  cards: readonly RankableCard[],
  options: {
    now: Date;
    seed: string;
    affinity?: ViewerAffinity;
    /** Set on a style shelf. For you leaves it unset and ignores angle hearts and covers. */
    style?: {
      style: Style;
      affinity: ViewerAffinity;
      hearts: number;
      /** Each card's primary tab for this viewer. Absent: no card is off-tab. */
      primaryByCard?: ReadonlyMap<string, Style>;
    };
  },
): ScoredCard[] {
  const shelf = options.style;
  return cards
    .map((card) => {
      const primary = shelf?.primaryByCard?.get(card.id);
      return scoreCard(card, {
        now: options.now,
        seed: options.seed,
        affinity: options.affinity,
        style: shelf
          ? {
              style: shelf.style,
              affinity: shelf.affinity,
              hearts: shelf.hearts,
              angleHearts: card.angleHearts ?? card.angleHeartsByStyle?.[shelf.style] ?? 0,
              coverMatches: card.coverStyle === shelf.style,
              offTab: primary !== undefined && primary !== shelf.style,
            }
          : undefined,
      });
    })
    .sort(compareRanked);
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
 * still decides which card comes next, so a page reads newest-first; the caps only stop a
 * bucket from taking more than its share, which pushes the other buckets' cards up. Their
 * sum is at least the page size, so the caps never leave a page short.
 */
export function bucketCaps(mix: ThemeMix, pageSize: number): Record<ThemeBucket, number> {
  const cap = (share: number): number => Math.ceil(share * pageSize - 1e-9);
  return { core: cap(mix.core), adjacent: cap(mix.adjacent), explore: cap(mix.explore) };
}

export const SPREAD_LIMITS = {
  /** Cards one author can hold in a page. */
  perAuthor: 2,
  /**
   * The viewer's own cards in a page. Never broken: For you is about other people, and
   * your posts are all on Profile.
   */
  own: 1,
  /** Consecutive cards allowed to share a life area, a dominant mood, or a cover angle. */
  run: 2,
  /**
   * The same run for a card on the viewer's own theme. Someone who is mostly in Work
   * should be able to stay there a beat longer; it is reading rhythm, not a cap.
   */
  coreRun: 3,
  /** Cards at the top intensity, so a page is never a wall of crisis. */
  peakIntensity: 6,
} as const;

/**
 * How follows shape a For you page. Following someone is a boost, not a filter: once the
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
  /** Set when the page follows a theme mix. Absent reads as `explore`. */
  bucket?: ThemeBucket;
  /** The viewer's own card. Capped at `SPREAD_LIMITS.own` and outside the theme mix. */
  own?: boolean;
  /** Written by someone the viewer follows. */
  followed?: boolean;
  createdAt?: Date;
};

/**
 * The follow floor for this viewer, or null while they follow too few people who post.
 * Counted over the whole candidate set, so every page of a visit uses the same rule.
 */
export function followMix(
  cards: readonly Pick<SpreadableCard, "authorId" | "followed" | "own" | "createdAt">[],
  now: Date,
): FollowMix | null {
  const recentSince = new Date(now.getTime() - FOLLOW_MIX.recentDays * 86_400_000);
  const authors = new Set<string>();
  for (const card of cards) {
    if (card.followed && !card.own && card.createdAt && card.createdAt >= recentSince) {
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
  own: number;
  followed: number;
  followedRecent: number;
  lastAuthor: string | null;
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
 * How badly a card fits where it would land. The author and intensity caps are real
 * limits — one voice dominating a page, or a wall of crisis, is the thing to prevent.
 * A run is only reading rhythm, so breaking one is better than breaking a cap. `never`
 * is the own-card cap, which no fallback breaks.
 */
type SpreadFit = "ok" | "soft" | "hard" | "never";

function spreadFit(card: SpreadableCard, state: SpreadState): SpreadFit {
  if (card.own && state.own >= SPREAD_LIMITS.own) {
    return "never";
  }
  if ((state.perAuthor.get(card.authorId) ?? 0) >= SPREAD_LIMITS.perAuthor) {
    return "hard";
  }
  if (card.intensity >= 5 && state.peakIntensity >= SPREAD_LIMITS.peakIntensity) {
    return "hard";
  }
  const themeRun = card.bucket === "core" ? SPREAD_LIMITS.coreRun : SPREAD_LIMITS.run;
  const breaksRun =
    card.authorId === state.lastAuthor ||
    runIsFull(state.category, card.category, themeRun) ||
    runIsFull(state.mood, dominantMood(card), themeRun) ||
    runIsFull(state.spotlight, card.spotlightStyle);
  return breaksRun ? "soft" : "ok";
}

function isRecentFollowed(card: SpreadableCard, follow: FollowMix | null | undefined): boolean {
  return Boolean(
    follow && card.followed && !card.own && card.createdAt && card.createdAt >= follow.recentSince,
  );
}

function recordSpread(card: SpreadableCard, state: SpreadState, follow: FollowMix | null | undefined): void {
  state.perAuthor.set(card.authorId, (state.perAuthor.get(card.authorId) ?? 0) + 1);
  if (card.own) {
    state.own += 1;
  }
  if (card.followed && !card.own) {
    state.followed += 1;
  }
  if (isRecentFollowed(card, follow)) {
    state.followedRecent += 1;
  }
  state.lastAuthor = card.authorId;
  if (card.intensity >= 5) {
    state.peakIntensity += 1;
  }
  state.category = extendRun(state.category, card.category);
  state.mood = extendRun(state.mood, dominantMood(card));
  state.spotlight = extendRun(state.spotlight, card.spotlightStyle);
}

function emptySpreadState(): SpreadState {
  return {
    perAuthor: new Map(),
    own: 0,
    followed: 0,
    followedRecent: 0,
    lastAuthor: null,
    peakIntensity: 0,
    category: { key: null, length: 0 },
    mood: { key: null, length: 0 },
    spotlight: { key: null, length: 0 },
  };
}

export type SpreadOptions = { mix?: ThemeMix | null; follow?: FollowMix | null };

/**
 * Greedy re-pick over one page: take the best-ranked card that does not break a limit.
 * Ranking decides what deserves to be read; this only decides what it is like to read in
 * a row. In order:
 *
 * 1. When the follow floor is behind (fewer than `share` of the slots so far), the best
 *    recent card from someone the viewer follows, if one fits without breaking a cap.
 * 2. The best-ranked card that fits and whose theme bucket (and the followed share) has
 *    room; then one that only breaks a rhythm rule; then the same ignoring that room.
 * 3. When every card left breaks the author or intensity cap (a small community), the
 *    card whose author has the fewest cards on the page, ties to rank. Never plain rank
 *    order, which would wall the page with the top author.
 * 4. Only own cards over their cap are left: the page ends short.
 */
export function spreadPage<T extends SpreadableCard>(
  ranked: readonly T[],
  pageSize: number,
  options: SpreadOptions = {},
): T[] {
  const state = emptySpreadState();
  const remaining = [...ranked];
  const page: T[] = [];
  const placed: Record<ThemeBucket, number> = { core: 0, adjacent: 0, explore: 0 };
  const caps = options.mix ? bucketCaps(options.mix, pageSize) : null;
  const follow = options.follow ?? null;
  const followCap = follow ? Math.ceil(follow.maxShare * pageSize - 1e-9) : Number.POSITIVE_INFINITY;

  const hasRoom = (card: T): boolean => {
    if (card.followed && !card.own && state.followed >= followCap) {
      return false;
    }
    if (card.own || !caps) {
      return true;
    }
    const bucket = card.bucket ?? "explore";
    return placed[bucket] < caps[bucket];
  };

  while (page.length < pageSize && remaining.length > 0) {
    const fits = remaining.map((card) => spreadFit(card, state));
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
    if (!card.own) {
      placed[card.bucket ?? "explore"] += 1;
    }
    page.push(card);
  }

  return page;
}

/**
 * The whole ranked list, spread one page at a time. The limits are per page, but the
 * result has to be one stable global order or offset paging would drop and repeat
 * cards as the offset moves — so the windows are computed the same way every request.
 *
 * Each page carries at most one of the viewer's own cards. Once nobody else's cards are
 * left the list ends; the rest of the viewer's own posts are on their Profile.
 */
export function spreadRanked<T extends SpreadableCard>(
  ranked: readonly T[],
  pageSize: number,
  options: SpreadOptions = {},
): T[] {
  const spread: T[] = [];
  let remaining: readonly T[] = ranked;
  while (remaining.length > 0) {
    const window = spreadPage(remaining, pageSize, options);
    if (window.length === 0) {
      break;
    }
    spread.push(...window);
    const taken = new Set(window.map((card) => card.id));
    remaining = remaining.filter((card) => !taken.has(card.id));
    if (!remaining.some((card) => !card.own)) {
      break;
    }
  }
  return spread;
}

/**
 * Share of a viewer's cards that open on the angle they keep hearting. Deliberately not
 * all of them: Home's For you tab exists to show mixed covers, and one style on every card
 * would make the feed read like a single voice.
 */
const PREFERRED_COVER_SHARE = 0.5;

/**
 * Which angle a card opens on for this viewer.
 *
 * Someone who hearts Humorous should meet Humorous more often, but the mix is the point
 * of the For you tab, so the choice is a stable coin flip per card rather than a takeover.
 * Deterministic in the card and the viewer, so a card does not change face on a reload.
 *
 * With `kept` (For you only), a card never opens on an answer the viewer already hearted
 * while it has one they have not: that card is back for the angles they have not read.
 */
export function openingStyle(options: {
  cardId: string;
  viewerId: string;
  cover: Style;
  available: readonly Style[];
  preferred: Style | null;
  kept?: ReadonlySet<Style>;
}): Style {
  const kept = options.kept;
  const unkept = kept ? options.available.filter((style) => !kept.has(style)) : options.available;
  const open = (style: Style): boolean => unkept.length === 0 || unkept.includes(style);
  const { preferred } = options;

  let face = options.cover;
  if (preferred && preferred !== options.cover && options.available.includes(preferred)) {
    face = jitterTerm(options.cardId, options.viewerId) < PREFERRED_COVER_SHARE ? preferred : options.cover;
  }
  if (open(face)) {
    return face;
  }
  if (preferred && open(preferred) && options.available.includes(preferred)) {
    return preferred;
  }
  // The next unkept angle after the cover, in catalog order, so one card always lands on one face.
  const start = STYLES.indexOf(options.cover);
  for (let step = 1; step <= STYLES.length; step += 1) {
    const style = STYLES[(start + step) % STYLES.length];
    if (style && unkept.includes(style)) {
      return style;
    }
  }
  return face;
}

/** A pull-to-refresh session: which order the viewer is walking and where it starts. */
export type FeedSession = {
  seed: string;
  startedAt: Date;
  offset: number;
};

/**
 * `seed|startedAt|offset`, base64url. Opaque on purpose: the client only echoes it
 * back, so the shape stays free to change without another App Store release.
 */
export function encodeFeedSession(session: FeedSession): string {
  const raw = `${session.seed}|${session.startedAt.toISOString()}|${session.offset}`;
  return Buffer.from(raw, "utf8").toString("base64url");
}

export function decodeFeedSession(raw: string): FeedSession | null {
  let decoded: string;
  try {
    decoded = Buffer.from(raw, "base64url").toString("utf8");
  } catch {
    return null;
  }
  const [seed, startedAt, offset] = decoded.split("|");
  if (!seed || !startedAt || offset === undefined) {
    return null;
  }
  if (!/^[A-Za-z0-9_-]{8,64}$/.test(seed)) {
    return null;
  }
  const started = new Date(startedAt);
  const parsedOffset = Number(offset);
  if (
    Number.isNaN(started.getTime()) ||
    !Number.isSafeInteger(parsedOffset) ||
    parsedOffset < 0
  ) {
    return null;
  }
  return { seed, startedAt: started, offset: parsedOffset };
}

/** Ranking is opt-in per deployment, so a bad feed is one variable away from gone. */
export function rankingEnabled(environment: NodeJS.ProcessEnv = process.env): boolean {
  return environment.FEED_RANKING?.trim().toLowerCase() === "resonance";
}
