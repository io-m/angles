/** Append only: app builds before the style set header know only the first four. */
export const STYLES = ["stoic", "hopeful", "witty", "tough", "tender", "values"] as const;

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

/** Closed set of thinking traps the decision call may name. The writer pushes against them. */
export const DISTORTIONS = [
  "catastrophizing",
  "mind_reading",
  "all_or_nothing",
  "overgeneralizing",
  "personalizing",
  "should_statements",
  "labeling",
  "fortune_telling",
  "emotional_reasoning",
  "discounting_positive",
] as const;

export type Distortion = (typeof DISTORTIONS)[number];

export const INTENSITY_BANDS = ["low", "mid", "high"] as const;

export type IntensityBand = (typeof INTENSITY_BANDS)[number];

export type FollowUpAnswer = {
  question: string;
  answer: string;
};

/** The signed cook a recook starts from, echoed exactly as `POST /reframe` returned it. */
export type RecookSource = {
  thought: string;
  thoughtOriginal?: string;
  meta: Omit<ReframeMeta, "matching"> & { matching?: MatchingKey };
  model: string;
  signature: string;
};

export type RecookRequest = {
  style: Style;
  cook: RecookSource;
  /** The signed answer being replaced. Absent for a style the cook did not write. */
  previous?: { reframe: string; reframeOriginal?: string; signature: string };
};

/** A compose turn sends `text`; a recook sends `recook` and skips the decision call. */
export type ReframeRequest = (
  | { text: string; followUps?: FollowUpAnswer[] }
  | { recook: RecookRequest }
) & {
  /** Device region (ISO 3166-1 alpha-2). Picks crisis contacts; never sent to the model. */
  region?: string;
};

export type ReframeResult = {
  style: Style;
  /** English. The only version anyone but the author sees. */
  reframe: string;
  /** The same answer in `meta.inputLanguage`, when that is not English. */
  reframeOriginal?: string;
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
  /** 0–2 thinking traps the thought shows. Signed with the cook; not stored on the card. */
  distortions: Distortion[];
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
  /** Local crisis contacts for the request's region. Present exactly when `safety` is not `none`. */
  crisisResource?: string;
  usage: ReframeUsage;
};

/** `taste` is the one free thought before a membership: 1 credit until it is used, then 0. */
export type UsagePlan = "taste" | "membership";

export type ReframeUsage = {
  creditsUsed: number;
  remaining: number;
  granted: number;
  resetsAt: string | null;
  warning: "normal" | "low" | "critical" | "empty";
  /** What one cook or recook costs. Flat: the server picks the model. */
  creditCost: number;
  plan: UsagePlan;
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
  /** The writer that answered. `POST /cards` echoes it; the phone never shows it. */
  model: string;
  /** Signs `thought`, `thoughtOriginal`, `model`, and `meta` (minus `matching`). */
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
  creditCost: number;
  plan: UsagePlan;
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
  /** Trimmed `users.name` when the API includes it (for example follow notifications). */
  displayName?: string;
  avatarUrl?: string;
  following: boolean;
};

export type FollowStateResponse = {
  following: boolean;
};

export type PushEnvironment = "sandbox" | "production";

export type FollowNotificationItem = {
  id: string;
  createdAt: string;
  readAt: string | null;
  followedBack: boolean;
  actor: StoredCardAuthor;
};

export type FollowNotificationsResponse = {
  unreadCount: number;
  notifications: FollowNotificationItem[];
};

/** `before` is the build 18 shape; current clients send `throughId`. */
export type ReadNotificationsRequest = { throughId: string } | { before: string };

export type ReadNotificationsResponse = {
  read: true;
  unreadCount: number;
};

export type NotifyFollowsBody = {
  notifyFollows: boolean;
};

export type DeviceRegistrationBody = {
  registered: boolean;
};

export type FollowingListResponse = {
  users: StoredCardAuthor[];
};

export type AuthorCardsResponse = {
  user: StoredCardAuthor;
  cards: StoredCard[];
};

export type ProfileBody = {
  initials: string;
  /** Trimmed display name. Empty when the account has never stored one. */
  name: string;
  avatarUrl?: string;
};

export type SessionBody = {
  id: string;
  initials: string;
  name: string;
  tasteCompletedAt: string | null;
  tasteConsumedAt: string | null;
  /** When this account agreed to the Terms (zero tolerance for abuse) and AI processing. */
  termsAcceptedAt: string | null;
  /** Push when someone follows this account. The in-app list stays either way. */
  notifyFollows: boolean;
  avatarUrl?: string;
};

export type TermsAcceptanceBody = {
  termsAcceptedAt: string;
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
  /** Sent to the author only; everyone else reads the English. */
  reframeOriginal?: string;
  /**
   * How many people saved the card while this angle was on screen. Present only on the
   * author's own public cards, so nobody can read another author's numbers. Omitted at zero.
   */
  saveCount?: number;
};

export const DECISION_KINDS = ["save", "pass"] as const;

export type DecisionKind = (typeof DECISION_KINDS)[number];

/** Most passes a card can take. At this count it never returns to the stack. */
export const MAX_PASSES = 2;

/**
 * The viewer's own record on someone else's card. A stack card carries it when it is
 * returning, so a rewind can write it back exactly; Saved cards carry their save.
 */
export type CardDecision = {
  kind: DecisionKind;
  /** The angle on screen when they decided. */
  style: Style;
  /** Every angle that had been on screen. Always includes `style`. */
  checkedStyles: Style[];
  passes: number;
  decidedAt: string;
};

/** `PUT /cards/:id/decision`. The full row, so a retry or a rewind writes the same state. */
export type DecisionBody = {
  kind: DecisionKind;
  style: Style;
  checkedStyles: Style[];
  passes: number;
};

export type DecisionResponse = {
  decision: CardDecision;
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
  /** The cover the author saved. */
  spotlightStyle: Style;
  /**
   * The angle this viewer opens the card on: the cover on your own card, the saved angle
   * on a saved card, and on the stack a ranked pick that is never an angle already seen.
   */
  openingStyle: Style;
  isPublic: boolean;
  createdAt: string;
  isOwner: boolean;
  /** A curated card from the Angles house account, not a person. */
  isHouse: boolean;
  /** The viewer's save or pass on someone else's card. Absent when they have not decided. */
  decision?: CardDecision;
  /** People who saved this card. Present only on the author's own public card; omitted at zero. */
  saveCount?: number;
  /**
   * True only on the owner's own card, and only while an operator hide is in force.
   * Absent everywhere else.
   */
  moderationHidden?: boolean;
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
  /** `true`: only cards the viewer saved. `false`: only their own. Absent: both. */
  saved?: boolean;
};

/** One visit to the stack. Opaque to the client, which echoes it back. */
export type FeedSessionCursor = {
  seed: string;
  startedAt: Date;
};

export type StackQuery = {
  limit: number;
  session: FeedSessionCursor;
  /** Cards this visit already handed out, newest last. Never sent again in the same visit. */
  seen: string[];
  /** Only these life areas, when set. */
  categories?: Category[];
  /** Only cards sharing at least one of these moods, when set. */
  emotions?: Emotion[];
};

export type StackResponse = {
  cards: StoredCard[];
  /** Echo it back for the next page of this visit. */
  session: string;
  /** Nothing is left after these cards, house cards included. The end card comes next. */
  exhausted: boolean;
};

export type FeedCursor = {
  createdAt: Date;
  id: string;
};

export type PatchCardInput = {
  isPublic: boolean;
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

export function matchingFor(meta: Pick<ReframeMeta, "category" | "tags" | "intensity">): MatchingKey {
  return { category: meta.category, tags: meta.tags, intensityBand: intensityBand(meta.intensity) };
}
