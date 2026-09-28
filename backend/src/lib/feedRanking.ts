import { createHash } from "node:crypto";
import type { Category, Emotion, Style } from "../types/index.js";

/**
 * Resonance ranking for the community feed.
 *
 * What it optimizes, in order: recognition (thoughts near what this viewer has been
 * writing about), relief (angles that demonstrably helped a stranger), a different
 * read on every pull, and exposure for posts nobody has found yet.
 *
 * What it refuses to optimize: dwell time, session length, and distress. Intensity is
 * capped by the spread pass, never rewarded — that is the doom-scroll lever and it
 * stays off. A useful reframe and a closed app is a success.
 */
export const RANKING_WEIGHTS = {
  freshness: 1.0,
  resonance: 0.8,
  affinity: 0.7,
  followed: 0.35,
  secondChance: 0.25,
  jitter: 0.15,
} as const;

/** Freshness half-scale in hours. Four days, not a news cycle: a reframe from last
 * week is as useful as one from this morning. */
const FRESHNESS_SCALE_HOURS = 96;

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
  hearts: number;
  followed: boolean;
};

/** What the viewer has been writing about, from their own recent cards. */
export type ViewerAffinity = {
  categories: ReadonlySet<Category>;
  emotions: ReadonlySet<Emotion>;
};

export const EMPTY_AFFINITY: ViewerAffinity = {
  categories: new Set<Category>(),
  emotions: new Set<Emotion>(),
};

export type RankingTerms = {
  freshness: number;
  resonance: number;
  affinity: number;
  followed: number;
  secondChance: number;
  jitter: number;
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

/** Overlap with the viewer's own recent life areas and moods. */
export function affinityTerm(card: RankableCard, affinity: ViewerAffinity): number {
  const category = affinity.categories.has(card.category) ? 1 : 0;
  const shared = card.emotions.filter((emotion) => affinity.emotions.has(emotion)).length;
  return 0.6 * category + 0.4 * Math.min(1, shared / 2);
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
  options: { now: Date; seed: string; affinity?: ViewerAffinity },
): ScoredCard {
  const affinity = options.affinity ?? EMPTY_AFFINITY;
  const terms: RankingTerms = {
    freshness: freshnessTerm(card, options.now),
    resonance: resonanceTerm(card),
    affinity: affinityTerm(card, affinity),
    followed: card.followed ? 1 : 0,
    secondChance: secondChanceTerm(card, options.now),
    jitter: jitterTerm(card.id, options.seed),
  };

  let score = 0;
  for (const key of Object.keys(RANKING_WEIGHTS) as (keyof RankingTerms)[]) {
    score += RANKING_WEIGHTS[key] * terms[key];
  }
  return { id: card.id, score, terms };
}

/** Highest first, ties broken by id so one seed always produces one order. */
export function rankCards(
  cards: readonly RankableCard[],
  options: { now: Date; seed: string; affinity?: ViewerAffinity },
): ScoredCard[] {
  return cards
    .map((card) => scoreCard(card, options))
    .sort((left, right) => right.score - left.score || (left.id < right.id ? 1 : -1));
}

export const SPREAD_LIMITS = {
  /** Cards one author can hold in a page. */
  perAuthor: 2,
  /** Consecutive cards allowed to share a life area, a dominant mood, or a cover angle. */
  run: 2,
  /** Cards at the top intensity, so a page is never a wall of crisis. */
  peakIntensity: 6,
} as const;

export type SpreadableCard = {
  id: string;
  authorId: string;
  category: Category;
  emotions: readonly Emotion[];
  intensity: number;
  spotlightStyle: Style;
};

type Run<T> = { key: T | null; length: number };

type SpreadState = {
  perAuthor: Map<string, number>;
  peakIntensity: number;
  category: Run<Category>;
  mood: Run<Emotion>;
  spotlight: Run<Style>;
};

function dominantMood(card: SpreadableCard): Emotion | null {
  return card.emotions[0] ?? null;
}

function runIsFull<T>(run: Run<T>, key: T | null): boolean {
  return key !== null && run.key === key && run.length >= SPREAD_LIMITS.run;
}

function extendRun<T>(run: Run<T>, key: T | null): Run<T> {
  return run.key === key && key !== null ? { key, length: run.length + 1 } : { key, length: 1 };
}

/**
 * How badly a card fits where it would land. The author and intensity caps are real
 * limits — one voice dominating a page, or a wall of crisis, is the thing to prevent.
 * A run is only reading rhythm, so breaking one is better than breaking a cap.
 */
type SpreadFit = "ok" | "soft" | "hard";

function spreadFit(card: SpreadableCard, state: SpreadState): SpreadFit {
  if ((state.perAuthor.get(card.authorId) ?? 0) >= SPREAD_LIMITS.perAuthor) {
    return "hard";
  }
  if (card.intensity >= 5 && state.peakIntensity >= SPREAD_LIMITS.peakIntensity) {
    return "hard";
  }
  const breaksRun =
    runIsFull(state.category, card.category) ||
    runIsFull(state.mood, dominantMood(card)) ||
    runIsFull(state.spotlight, card.spotlightStyle);
  return breaksRun ? "soft" : "ok";
}

function recordSpread(card: SpreadableCard, state: SpreadState): void {
  state.perAuthor.set(card.authorId, (state.perAuthor.get(card.authorId) ?? 0) + 1);
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
    peakIntensity: 0,
    category: { key: null, length: 0 },
    mood: { key: null, length: 0 },
    spotlight: { key: null, length: 0 },
  };
}

/**
 * Greedy re-pick over one page: take the best-ranked card that does not break a limit,
 * and fall back to the best remaining card rather than returning a short page. Ranking
 * decides what deserves to be read; this only decides what it is like to read in a row.
 */
export function spreadPage<T extends SpreadableCard>(
  ranked: readonly T[],
  pageSize: number,
): T[] {
  const state = emptySpreadState();
  const remaining = [...ranked];
  const page: T[] = [];

  while (page.length < pageSize && remaining.length > 0) {
    const fits = remaining.map((card) => spreadFit(card, state));
    // Best-ranked card that fits; failing that, one that only breaks a rhythm rule;
    // failing that, rank order wins over returning a short page.
    let index = fits.indexOf("ok");
    if (index === -1) {
      index = fits.indexOf("soft");
    }
    if (index === -1) {
      index = 0;
    }
    const [card] = remaining.splice(index, 1);
    if (!card) {
      break;
    }
    recordSpread(card, state);
    page.push(card);
  }

  return page;
}

/**
 * The whole ranked list, spread one page at a time. The limits are per page, but the
 * result has to be one stable global order or offset paging would drop and repeat
 * cards as the offset moves — so the windows are computed the same way every request.
 */
export function spreadRanked<T extends SpreadableCard>(
  ranked: readonly T[],
  pageSize: number,
): T[] {
  const spread: T[] = [];
  let remaining: readonly T[] = ranked;
  while (remaining.length > 0) {
    const window = spreadPage(remaining, pageSize);
    spread.push(...window);
    const taken = new Set(window.map((card) => card.id));
    remaining = remaining.filter((card) => !taken.has(card.id));
  }
  return spread;
}

/**
 * Share of a viewer's cards that open on the angle they keep hearting. Deliberately not
 * all of them: Home's All tab exists to show mixed covers, and one style on every card
 * would make the feed read like a single voice.
 */
const PREFERRED_COVER_SHARE = 0.5;

/**
 * Which angle a card opens on for this viewer.
 *
 * Someone who hearts Humorous should meet Humorous more often, but the mix is the point
 * of the All tab, so the choice is a stable coin flip per card rather than a takeover.
 * Deterministic in the card and the viewer, so a card does not change face on a reload.
 */
export function openingStyle(options: {
  cardId: string;
  viewerId: string;
  cover: Style;
  available: readonly Style[];
  preferred: Style | null;
}): Style {
  const { preferred } = options;
  if (!preferred || preferred === options.cover || !options.available.includes(preferred)) {
    return options.cover;
  }
  return jitterTerm(options.cardId, options.viewerId) < PREFERRED_COVER_SHARE
    ? preferred
    : options.cover;
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
