export const STYLES = ["stoic", "optimistic", "humorous", "tough_love"] as const;

export type Style = (typeof STYLES)[number];

/** Closed set. The model must pick one; `other` requires a proposed category. */
export const CATEGORIES = [
  "work",
  "money",
  "romantic",
  "family",
  "friends_social",
  "health",
  "self_worth",
  "future",
  "grief_loss",
  "identity",
  "other",
] as const;

export type Category = (typeof CATEGORIES)[number];

export const EMOTIONS = [
  "anger",
  "shame",
  "fear",
  "sadness",
  "envy",
  "loneliness",
  "overwhelm",
  "numbness",
  "hope",
] as const;

export type Emotion = (typeof EMOTIONS)[number];

export const TIMEFRAMES = ["past", "ongoing", "future"] as const;

export type Timeframe = (typeof TIMEFRAMES)[number];

export const SAFETY_FLAGS = ["none", "self_harm", "harm_others", "abuse"] as const;

export type SafetyFlag = (typeof SAFETY_FLAGS)[number];

export const INTENSITY_BANDS = ["low", "mid", "high"] as const;

export type IntensityBand = (typeof INTENSITY_BANDS)[number];

export type FollowUpAnswer = {
  question: string;
  answer: string;
};

export type ReframeRequest = {
  text: string;
  followUps?: FollowUpAnswer[];
  styles?: Style[];
  model?: string;
};

export type ReframeResult = {
  style: Style;
  reframe: string;
};

export type SkippedStyle = {
  style: Style;
  reason: string;
};

/** Anonymous similarity key for later community matching. Never carries text. */
export type MatchingKey = {
  category: Category;
  tags: string[];
  intensityBand: IntensityBand;
};

export type ReframeMeta = {
  category: Category;
  proposedCategory?: string;
  proposedLabel?: string;
  tags: string[];
  intensity: number;
  timeframe: Timeframe;
  emotions: Emotion[];
  safety: SafetyFlag;
  inputLanguage: string;
  skippedStyles: SkippedStyle[];
  matching: MatchingKey;
};

export type ContinueResponse = {
  kind: "continue";
  message: string;
  options: string[];
  safety: SafetyFlag;
};

export type ReadyResponse = {
  kind: "ready";
  thought: string;
  thoughtOriginal?: string;
  results: ReframeResult[];
  meta: ReframeMeta;
};

export type ReframeResponse = ContinueResponse | ReadyResponse;

export type ApiErrorBody = {
  error: string;
  code: string;
};

export type StoredCardTag = {
  slug: string;
  label: string;
};

export type StoredCardAuthor = {
  initials: string;
};

export type StoredReframeResult = {
  style: Style;
  reframe: string;
  isFavorite: boolean;
  favoritedAt?: string;
};

export type StoredCard = {
  id: string;
  thought: string;
  thoughtOriginal?: string;
  inputLanguage: string;
  category: Category;
  proposedCategory?: string;
  proposedLabel?: string;
  tags: StoredCardTag[];
  intensity: number;
  intensityBand: IntensityBand;
  timeframe: Timeframe;
  emotions: Emotion[];
  safety: SafetyFlag;
  skippedStyles: SkippedStyle[];
  matching: MatchingKey;
  results: StoredReframeResult[];
  model: string;
  spotlightStyle: Style;
  isPinned: boolean;
  pinnedAt?: string;
  isPublic: boolean;
  createdAt: string;
  isOwner: boolean;
  author: StoredCardAuthor;
};

export type CreateCardInput = {
  thought: string;
  thoughtOriginal?: string;
  results: ReframeResult[];
  meta: Omit<ReframeMeta, "matching">;
  model: string;
  spotlightStyle: Style;
};

export type CardListQuery = {
  limit: number;
  before?: Date;
  category?: Category;
  /** Cards that include this style in `results`. Cover (`spotlightStyle`) is display-only. */
  style?: Style;
  /** Cards that have at least one liked style (owner heart or viewer save). */
  favorite?: boolean;
  pinned?: boolean;
};

export type FeedListQuery = {
  limit: number;
  before?: Date;
  category?: Category;
  style?: Style;
  emotion?: Emotion;
};

export type FeedHomeQuery = {
  /** Cards that include this style in `results`. Home shelves are capped, so the filter runs in SQL. */
  style?: Style;
  perSection: number;
};

export type FeedHomeSectionKind = "category" | "emotion";

export type FeedHomeSection = {
  kind: FeedHomeSectionKind;
  id: Category | Emotion;
  cardIds: string[];
};

/** Cards are de-duplicated: one card may be listed by a domain shelf and several mood shelves. */
export type FeedHomeResponse = {
  cards: StoredCard[];
  recent: string[];
  sections: FeedHomeSection[];
};

export type PatchCardInput = {
  isFavorite?: boolean;
  style?: Style;
  isPinned?: boolean;
  isPublic?: boolean;
};

const STYLE_SET: ReadonlySet<string> = new Set(STYLES);

export function isStyle(value: string): value is Style {
  return STYLE_SET.has(value);
}

export function intensityBand(intensity: number): IntensityBand {
  if (intensity <= 2) {
    return "low";
  }
  if (intensity === 3) {
    return "mid";
  }
  return "high";
}
