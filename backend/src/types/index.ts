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
  usage: ReframeUsage;
};

export type ReframeUsage = {
  creditsUsed: number;
  remaining: number;
  granted: number;
  resetsAt: string | null;
  warning: "normal" | "low" | "critical" | "empty";
  allowedModels: Array<"mistral-small-latest" | "deepseek-flash" | "gemini-3.8-flash">;
  creditCost: number;
};

/** A reframe the server produced. `POST /cards` only accepts results it signed. */
export type SignedReframeResult = ReframeResult & {
  signature: string;
};

export type ReadyResponse = {
  kind: "ready";
  thought: string;
  thoughtOriginal?: string;
  results: SignedReframeResult[];
  meta: ReframeMeta;
  /** Signs `thought`, `thoughtOriginal`, and `meta` (minus `matching`). */
  signature: string;
  usage: ReframeUsage;
};

export type ProfileUsageBody = {
  creditsGranted: number;
  creditsRemaining: number;
  periodStart: string | null;
  periodEnd: string | null;
  resetsAt: string | null;
  warning: ReframeUsage["warning"];
  allowedModels: ReframeUsage["allowedModels"];
  creditCost: Record<ReframeUsage["allowedModels"][number], number>;
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
  id: string;
  initials: string;
  avatarUrl?: string;
  following: boolean;
};

export type FollowStateResponse = {
  following: boolean;
};

export type FollowingListResponse = {
  users: StoredCardAuthor[];
};

export type AuthorCardsResponse = {
  user: StoredCardAuthor;
  cards: StoredCard[];
};

export type ModelCardsResponse = {
  model: string;
  cards: StoredCard[];
};

export type ProfileBody = {
  initials: string;
  avatarUrl?: string;
};

export type SessionBody = {
  id: string;
  initials: string;
  name: string;
  tasteCompletedAt: string | null;
  tasteConsumedAt: string | null;
  avatarUrl?: string;
};

export type SubscriptionBody = {
  isEntitled: boolean;
  status: "active" | "grace" | "billing_retry" | "expired" | "revoked" | null;
  productId: "app.angles.ios.annual" | "app.angles.ios.monthly" | null;
  environment: "sandbox" | "production" | null;
  paidThrough: string | null;
  revokedAt: string | null;
  quotaAnchor: string | null;
  updatedAt: string | null;
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
  isPublic?: boolean;
};

export type CardListQuery = {
  limit: number;
  before?: FeedCursor;
  category?: Category;
  /** Cards that include this style in `results`. Cover (`spotlightStyle`) is display-only. */
  style?: Style;
  /** Cards that have at least one liked style (owner heart or viewer save). */
  favorite?: boolean;
};

export type FeedListQuery = {
  limit: number;
  before?: FeedCursor;
  categories?: Category[];
  emotions?: Emotion[];
  /** Cards that include this style in `results`. Cover (`spotlightStyle`) is display-only. */
  style?: Style;
};

export type FeedCursor = {
  createdAt: Date;
  id: string;
};

export type PatchCardInput = {
  isFavorite?: boolean;
  style?: Style;
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
