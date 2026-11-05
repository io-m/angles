/**
 * The shape of a believable community, decided without touching the database.
 *
 * The fixture posts are flat on purpose: 30 per life area, 7 per author, every one dated
 * weeks ago, no saves. A stack ranked on time, saves and themes has nothing to work with
 * there. This turns the same posts into something that looks like real use: a busy last
 * day, prolific and quiet authors, themes that trend, and readers with tastes.
 *
 * Pure and seeded, so a run is reproducible and the unit test can check the invariants.
 */
import { CATEGORIES, STYLES, intensityBand, type Category, type Style } from "../types/index.js";

export type Rng = () => number;

/** Small, fast, deterministic. */
export function mulberry32(seed: number): Rng {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4_294_967_296;
  };
}

function gaussian(rng: Rng): number {
  const u = Math.max(rng(), 1e-9);
  const v = rng();
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
}

function weightedIndex(rng: Rng, weights: readonly number[]): number {
  const total = weights.reduce((sum, weight) => sum + weight, 0);
  let target = rng() * total;
  for (const [index, weight] of weights.entries()) {
    target -= weight;
    if (target <= 0) {
      return index;
    }
  }
  return weights.length - 1;
}

function shuffled<T>(items: readonly T[], rng: Rng): T[] {
  const copy = [...items];
  for (let index = copy.length - 1; index > 0; index -= 1) {
    const swap = Math.floor(rng() * (index + 1));
    [copy[index], copy[swap]] = [copy[swap] as T, copy[index] as T];
  }
  return copy;
}

const HOUR_MS = 3_600_000;
const DAY_MS = 24 * HOUR_MS;

export const SHAPE = {
  /** Posts in the last 24 hours, a few of them inside the last two. */
  lastDay: 20,
  justPosted: 3,
  /** How far back the tail reaches. */
  spanDays: 45,
  /** No author holds more than this many posts, so the per-author cap is exercised but real. */
  maxPerAuthor: 25,
  readers: 40,
} as const;

/** Local evening and morning peaks, quiet nights. Index is the hour of the day. */
const HOUR_WEIGHTS = [
  1, 1, 1, 1, 1, 2, 3, 5, 6, 5, 4, 4, 5, 5, 4, 4, 4, 5, 6, 8, 10, 11, 9, 4,
] as const;

/** Lower is more recent. Work-life themes trend; grief and identity trail. */
const RECENCY_BIAS: Record<Category, number> = {
  work: -0.35,
  money: -0.3,
  self_worth: -0.3,
  future: -0.1,
  romantic: -0.1,
  health: 0,
  family: 0,
  friends_social: 0,
  other: 0.05,
  grief_loss: 0.3,
  identity: 0.3,
};

/** Skewed towards the middle: most days are a 3 or a 4, few are a 1 or a 5. */
const INTENSITY_WEIGHTS = [10, 20, 30, 25, 15] as const;

export type PostInput = { id: string; category: Category };

export type PostPlan = {
  id: string;
  userId: string;
  createdAt: Date;
  intensity: number;
  intensityBand: ReturnType<typeof intensityBand>;
};

function postingTimes(count: number, now: Date, rng: Rng): Date[] {
  const times: number[] = [];
  const lastDay = Math.min(SHAPE.lastDay, count);

  for (let index = 0; index < lastDay; index += 1) {
    if (index < SHAPE.justPosted) {
      // A few inside the last two hours, so "just posted" has something to show.
      times.push(now.getTime() - (0.2 + index * 0.6 + rng() * 0.3) * HOUR_MS);
    } else {
      times.push(now.getTime() - (2 + rng() * 22) * HOUR_MS);
    }
  }

  const remaining = count - lastDay;
  const perDay = Math.max(1, Math.round(remaining / (SHAPE.spanDays - 1)));
  let placed = 0;
  for (let day = 1; placed < remaining; day = (day % (SHAPE.spanDays - 1)) + 1) {
    const jitter = Math.round((rng() - 0.5) * 4);
    const todays = Math.min(remaining - placed, Math.max(0, perDay + jitter));
    for (let index = 0; index < todays; index += 1) {
      const hour = weightedIndex(rng, HOUR_WEIGHTS);
      const startOfDay = new Date(now.getTime() - day * DAY_MS);
      // The clock peaks are local evenings, and the community lives around UTC+2.
      startOfDay.setUTCHours((hour + 22) % 24, Math.floor(rng() * 60), Math.floor(rng() * 60), 0);
      let time = startOfDay.getTime();
      // Keep the tail strictly older than the busy last day.
      if (time > now.getTime() - DAY_MS) {
        time -= DAY_MS;
      }
      times.push(time);
    }
    placed += todays;
  }

  return times.sort((left, right) => right - left).map((time) => new Date(time));
}

function authorAssignment(count: number, authorIds: readonly string[], rng: Rng): string[] {
  // Rank the authors once, so the same few are prolific across the whole run.
  const ranked = shuffled(authorIds, rng);
  const weights = ranked.map((_, rank) => 1 / (rank + 1) ** 0.85);
  const held = new Map<string, number>();
  const assigned: string[] = [];

  // Everyone posts at least once, then the rest follow the power law up to the cap.
  for (const author of ranked.slice(0, count)) {
    assigned.push(author);
    held.set(author, 1);
  }
  while (assigned.length < count) {
    const author = ranked[weightedIndex(rng, weights)] as string;
    if ((held.get(author) ?? 0) >= SHAPE.maxPerAuthor) {
      continue;
    }
    held.set(author, (held.get(author) ?? 0) + 1);
    assigned.push(author);
  }
  return shuffled(assigned, rng);
}

export function planPosts(
  posts: readonly PostInput[],
  authorIds: readonly string[],
  now: Date,
  rng: Rng,
): PostPlan[] {
  const times = postingTimes(posts.length, now, rng);
  const authors = authorAssignment(posts.length, authorIds, rng);

  // The most recent slots go to the posts whose theme is trending.
  const order = posts
    .map((post) => ({ post, key: rng() + RECENCY_BIAS[post.category] }))
    .sort((left, right) => left.key - right.key)
    .map((entry) => entry.post);

  return order.map((post, index) => {
    const intensity = weightedIndex(rng, INTENSITY_WEIGHTS) + 1;
    return {
      id: post.id,
      userId: authors[index] as string,
      createdAt: times[index] as Date,
      intensity,
      intensityBand: intensityBand(intensity),
    };
  });
}

export type DecidableCard = {
  id: string;
  category: Category;
  createdAt: Date;
  styles: readonly Style[];
};

export type DecisionPlan = {
  userId: string;
  cardId: string;
  kind: "save" | "pass";
  style: Style;
  checkedStyles: Style[];
  passes: number;
  decidedAt: Date;
};

export type ReaderPlan = {
  id: string;
  initials: string;
  categories: Category[];
  style: Style;
  decisions: DecisionPlan[];
};

export function readerId(index: number): string {
  return `00000000-0000-4000-8300-${String(index + 1).padStart(12, "0")}`;
}

export const READER_EMAIL_PREFIX = "seed-reader-";

const THEME_POPULARITY: Record<Category, number> = {
  work: 10,
  self_worth: 9,
  money: 7,
  future: 6,
  romantic: 6,
  health: 5,
  family: 5,
  friends_social: 4,
  identity: 3,
  grief_loss: 3,
  other: 0,
};

const STYLE_POPULARITY: Record<Style, number> = {
  stoic: 30,
  hopeful: 28,
  witty: 24,
  tough: 18,
  tender: 16,
  values: 14,
};

/** Passes per save for a reader: most cards in a stack are swiped past. */
const PASSES_PER_SAVE = 2;

/** A decision some hours after the post lands, more often within the day; never in the future. */
function decidedAfter(card: DecidableCard, now: Date, rng: Rng): Date | null {
  const delayMs = -Math.log(Math.max(rng(), 1e-6)) * 8 * HOUR_MS;
  const at = new Date(Math.min(now.getTime() - 60_000, card.createdAt.getTime() + 5 * 60_000 + delayMs));
  return at.getTime() > card.createdAt.getTime() ? at : null;
}

/**
 * Readers with tastes, saving a heavy-tailed subset: most posts get nothing, a few are
 * loved. Each reader also passes on about twice as many as they save, after reading an
 * angle or two. One decision per reader and card, dated after the post and never in the
 * future.
 */
export function planReaders(cards: readonly DecidableCard[], now: Date, rng: Rng): ReaderPlan[] {
  const themeCategories = CATEGORIES.filter((category) => category !== "other");
  const themeWeights = themeCategories.map((category) => THEME_POPULARITY[category]);
  // How appealing each post is, lognormal, so a handful run away with the saves.
  const appeal = new Map(cards.map((card) => [card.id, Math.exp(1.5 * gaussian(rng))]));

  return Array.from({ length: SHAPE.readers }, (_, index) => {
    const categories = new Set<Category>();
    const themeCount = rng() < 0.6 ? 1 : 2;
    while (categories.size < themeCount) {
      categories.add(themeCategories[weightedIndex(rng, themeWeights)] as Category);
    }
    const style = STYLES[weightedIndex(rng, STYLES.map((item) => STYLE_POPULARITY[item]))] as Style;
    // Some readers are devoted, most drop in.
    const activity = Math.max(2, Math.round(3 + Math.exp(1.1 * gaussian(rng)) * 3));
    const recency = (card: DecidableCard): number =>
      // Readers find newer posts more, and older ones keep a trickle.
      0.3 + Math.exp(-(now.getTime() - card.createdAt.getTime()) / (10 * DAY_MS));

    const savePool = cards.map((card) => ({
      card,
      weight: (appeal.get(card.id) ?? 1) * (categories.has(card.category) ? 5 : 1) * recency(card),
    }));
    const passPool = cards.map((card) => ({
      card,
      weight: (categories.has(card.category) ? 0.5 : 1) * recency(card),
    }));

    const decisions: DecisionPlan[] = [];
    const taken = new Set<string>();
    const userId = readerId(index);
    for (let attempt = 0; decisions.length < activity && attempt < activity * 6; attempt += 1) {
      const { card } = savePool[weightedIndex(rng, savePool.map((entry) => entry.weight))] as (typeof savePool)[number];
      if (card.styles.length === 0 || taken.has(card.id)) {
        continue;
      }
      const chosen =
        card.styles.includes(style) && rng() < 0.55
          ? style
          : (card.styles[Math.floor(rng() * card.styles.length)] as Style);
      const decidedAt = decidedAfter(card, now, rng);
      if (!decidedAt) {
        continue;
      }
      taken.add(card.id);
      const opened = card.styles[0] as Style;
      decisions.push({
        userId,
        cardId: card.id,
        kind: "save",
        style: chosen,
        checkedStyles: [...new Set([opened, chosen])],
        passes: 0,
        decidedAt,
      });
    }

    const passTarget = decisions.length * PASSES_PER_SAVE;
    let passed = 0;
    for (let attempt = 0; passed < passTarget && attempt < passTarget * 6; attempt += 1) {
      const { card } = passPool[weightedIndex(rng, passPool.map((entry) => entry.weight))] as (typeof passPool)[number];
      if (card.styles.length === 0 || taken.has(card.id)) {
        continue;
      }
      const decidedAt = decidedAfter(card, now, rng);
      if (!decidedAt) {
        continue;
      }
      taken.add(card.id);
      const read = card.styles.slice(0, rng() < 0.7 ? 1 : 2);
      decisions.push({
        userId,
        cardId: card.id,
        kind: "pass",
        style: read[read.length - 1] as Style,
        checkedStyles: read,
        passes: 1,
        decidedAt,
      });
      passed += 1;
    }

    return {
      id: userId,
      initials: `R${(index + 1) % 10}`,
      categories: [...categories],
      style,
      decisions,
    };
  });
}

/**
 * A small taste for the phone account: a couple of life areas saved, mostly on Stoic and
 * Tough, on posts a few days old, over the last few days; and a few passes elsewhere.
 */
export function planViewerDecisions(
  userId: string,
  cards: readonly DecidableCard[],
  now: Date,
  rng: Rng,
): DecisionPlan[] {
  const themes: Category[] = ["work", "self_worth"];
  const styles: Style[] = ["stoic", "tough"];
  const inWindow = (card: DecidableCard): boolean => {
    const age = now.getTime() - card.createdAt.getTime();
    return age >= 3 * DAY_MS && age <= 14 * DAY_MS;
  };
  const saved = shuffled(
    cards.filter((card) => themes.includes(card.category) && inWindow(card)),
    rng,
  ).slice(0, 8);
  const passed = shuffled(
    cards.filter((card) => !themes.includes(card.category) && inWindow(card)),
    rng,
  ).slice(0, 4);
  // Spread over the last three days, oldest first.
  const at = (index: number, count: number) => new Date(now.getTime() - (3 * DAY_MS * (count - index)) / count);

  return [
    ...saved.flatMap((card, index): DecisionPlan[] => {
      const style = styles[index % styles.length] as Style;
      if (!card.styles.includes(style)) {
        return [];
      }
      const decidedAt = at(index, saved.length);
      if (decidedAt <= card.createdAt) {
        return [];
      }
      return [{ userId, cardId: card.id, kind: "save", style, checkedStyles: [style], passes: 0, decidedAt }];
    }),
    ...passed.flatMap((card, index): DecisionPlan[] => {
      const style = card.styles[0];
      const decidedAt = at(index, passed.length);
      if (!style || decidedAt <= card.createdAt) {
        return [];
      }
      return [{ userId, cardId: card.id, kind: "pass", style, checkedStyles: [style], passes: 1, decidedAt }];
    }),
  ];
}
