import { relations, sql } from "drizzle-orm";
import {
  bigint,
  boolean,
  check,
  date,
  index,
  integer,
  jsonb,
  pgEnum,
  pgTable,
  primaryKey,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from "drizzle-orm/pg-core";
import {
  CATEGORIES,
  EMOTIONS,
  INTENSITY_BANDS,
  SAFETY_FLAGS,
  STYLES,
  TIMEFRAMES,
  type SkippedStyle,
} from "../types/index.js";
import { REPORT_REASONS } from "../lib/communitySafetyTypes.js";

export const styleEnum = pgEnum("style", [...STYLES]);
export const categoryEnum = pgEnum("category", [...CATEGORIES]);
export const emotionEnum = pgEnum("emotion", [...EMOTIONS]);
export const timeframeEnum = pgEnum("timeframe", [...TIMEFRAMES]);
export const safetyFlagEnum = pgEnum("safety_flag", [...SAFETY_FLAGS]);
export const intensityBandEnum = pgEnum("intensity_band", [...INTENSITY_BANDS]);
export const reportReasonEnum = pgEnum("report_reason", [...REPORT_REASONS]);
export const subscriptionEnvironmentEnum = pgEnum("subscription_environment", [
  "sandbox",
  "production",
]);
export const subscriptionStatusEnum = pgEnum("subscription_status", [
  "active",
  "grace",
  "billing_retry",
  "expired",
  "revoked",
]);
export const meterOperationKindEnum = pgEnum("meter_operation_kind", ["full", "recook"]);
export const meterOperationStateEnum = pgEnum("meter_operation_state", [
  "running",
  "ready",
  "continue",
  "failed",
  "expired",
]);
export const meterResultKindEnum = pgEnum("meter_result_kind", ["ready", "continue"]);
export const llmCallKindEnum = pgEnum("llm_call_kind", [
  "decision",
  "batch",
  "reframe",
  "moderation",
]);
export const llmCallStatusEnum = pgEnum("llm_call_status", ["succeeded", "failed"]);
export const usageSourceEnum = pgEnum("usage_source", ["reported", "estimated"]);

export const users = pgTable(
  "users",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    name: text("name").notNull().default(""),
    email: text("email").notNull(),
    emailVerified: boolean("email_verified").notNull().default(false),
    image: text("image"),
    initials: text("initials").notNull(),
    avatarKey: text("avatar_key"),
    tasteCompletedAt: timestamp("taste_completed_at", { withTimezone: true, mode: "date" }),
    tasteConsumedAt: timestamp("taste_consumed_at", { withTimezone: true, mode: "date" }),
    createdAt: timestamp("created_at", { withTimezone: true, mode: "date" }).notNull().defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true, mode: "date" }).notNull().defaultNow(),
  },
  (table) => [
    uniqueIndex("users_email_unique").on(table.email),
    check("users_initials_len", sql`char_length(initials) between 1 and 2`),
  ],
);

export const sessions = pgTable("sessions", {
  id: text("id").primaryKey(),
  expiresAt: timestamp("expires_at", { withTimezone: true, mode: "date" }).notNull(),
  token: text("token").notNull().unique(),
  createdAt: timestamp("created_at", { withTimezone: true, mode: "date" }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true, mode: "date" }).notNull().defaultNow(),
  ipAddress: text("ip_address"),
  userAgent: text("user_agent"),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
});

export const accounts = pgTable("accounts", {
  id: text("id").primaryKey(),
  accountId: text("account_id").notNull(),
  providerId: text("provider_id").notNull(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  accessToken: text("access_token"),
  refreshToken: text("refresh_token"),
  idToken: text("id_token"),
  accessTokenExpiresAt: timestamp("access_token_expires_at", { withTimezone: true, mode: "date" }),
  refreshTokenExpiresAt: timestamp("refresh_token_expires_at", {
    withTimezone: true,
    mode: "date",
  }),
  scope: text("scope"),
  password: text("password"),
  createdAt: timestamp("created_at", { withTimezone: true, mode: "date" }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true, mode: "date" }).notNull().defaultNow(),
});

export const verifications = pgTable("verifications", {
  id: text("id").primaryKey(),
  identifier: text("identifier").notNull(),
  value: text("value").notNull(),
  expiresAt: timestamp("expires_at", { withTimezone: true, mode: "date" }).notNull(),
  createdAt: timestamp("created_at", { withTimezone: true, mode: "date" }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true, mode: "date" }).notNull().defaultNow(),
});

export const subscriptionEntitlements = pgTable(
  "subscription_entitlements",
  {
    userId: uuid("user_id")
      .primaryKey()
      .references(() => users.id, { onDelete: "cascade" }),
    originalTransactionId: text("original_transaction_id").notNull(),
    currentTransactionId: text("current_transaction_id").notNull(),
    productId: text("product_id").notNull(),
    environment: subscriptionEnvironmentEnum("environment").notNull(),
    status: subscriptionStatusEnum("status").notNull(),
    paidThrough: timestamp("paid_through", { withTimezone: true, mode: "date" }).notNull(),
    gracePeriodExpiresAt: timestamp("grace_period_expires_at", {
      withTimezone: true,
      mode: "date",
    }),
    renewalDate: timestamp("renewal_date", { withTimezone: true, mode: "date" }),
    revokedAt: timestamp("revoked_at", { withTimezone: true, mode: "date" }),
    quotaAnchor: timestamp("quota_anchor", { withTimezone: true, mode: "date" }).notNull(),
    lastAppleEventAt: timestamp("last_apple_event_at", {
      withTimezone: true,
      mode: "date",
      precision: 3,
    }).notNull(),
    createdAt: timestamp("created_at", { withTimezone: true, mode: "date" }).notNull().defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true, mode: "date" }).notNull().defaultNow(),
  },
  (table) => [
    uniqueIndex("subscription_entitlements_original_transaction_unique").on(
      table.originalTransactionId,
    ),
    uniqueIndex("subscription_entitlements_current_transaction_unique").on(
      table.currentTransactionId,
    ),
    index("subscription_entitlements_access_idx").on(table.userId, table.status, table.paidThrough),
    check(
      "subscription_entitlements_product_id",
      sql`${table.productId} in ('app.angles.ios.annual', 'app.angles.ios.monthly')`,
    ),
  ],
);

export const subscriptionEvents = pgTable(
  "subscription_events",
  {
    notificationUuid: uuid("notification_uuid").primaryKey(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    notificationType: text("notification_type").notNull(),
    subtype: text("subtype"),
    originalTransactionId: text("original_transaction_id").notNull(),
    transactionId: text("transaction_id").notNull(),
    signedAt: timestamp("signed_at", { withTimezone: true, mode: "date", precision: 3 }).notNull(),
    createdAt: timestamp("created_at", { withTimezone: true, mode: "date" }).notNull().defaultNow(),
  },
  (table) => [
    uniqueIndex("subscription_events_notification_metadata_unique").on(
      table.notificationUuid,
      table.notificationType,
      table.subtype,
    ),
    index("subscription_events_user_signed_idx").on(table.userId, table.signedAt.desc()),
  ],
);

export const usagePeriods = pgTable(
  "usage_periods",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    ownerId: uuid("owner_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    entitlementUserId: uuid("entitlement_user_id").references(
      () => subscriptionEntitlements.userId,
      { onDelete: "set null" },
    ),
    startsAt: timestamp("starts_at", { withTimezone: true, mode: "date", precision: 3 }).notNull(),
    endsAt: timestamp("ends_at", { withTimezone: true, mode: "date", precision: 3 }).notNull(),
    grantedCredits: integer("granted_credits").notNull(),
    reservedCredits: integer("reserved_credits").notNull().default(0),
    chargedCredits: integer("charged_credits").notNull().default(0),
    planVersion: text("plan_version").notNull(),
    tariffVersion: text("tariff_version").notNull(),
    createdAt: timestamp("created_at", { withTimezone: true, mode: "date" }).notNull().defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true, mode: "date" }).notNull().defaultNow(),
  },
  (table) => [
    uniqueIndex("usage_periods_owner_start_unique").on(table.ownerId, table.startsAt),
    index("usage_periods_owner_ends_idx").on(table.ownerId, table.endsAt),
    check("usage_periods_nonnegative", sql`
      ${table.grantedCredits} >= 0
      and ${table.reservedCredits} >= 0
      and ${table.chargedCredits} >= 0
    `),
    check(
      "usage_periods_within_grant",
      sql`${table.reservedCredits} + ${table.chargedCredits} <= ${table.grantedCredits}`,
    ),
    check("usage_periods_valid_range", sql`${table.endsAt} > ${table.startsAt}`),
  ],
);

export const meterOperations = pgTable(
  "meter_operations",
  {
    id: uuid("id").primaryKey(),
    ownerId: uuid("owner_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    clientRequestId: uuid("client_request_id").notNull(),
    requestFingerprint: text("request_fingerprint").notNull(),
    periodId: uuid("period_id").references(() => usagePeriods.id, { onDelete: "restrict" }),
    model: text("model").notNull(),
    kind: meterOperationKindEnum("kind").notNull(),
    reservedCredits: integer("reserved_credits").notNull().default(0),
    chargedCredits: integer("charged_credits").notNull().default(0),
    state: meterOperationStateEnum("state").notNull(),
    leaseExpiresAt: timestamp("lease_expires_at", {
      withTimezone: true,
      mode: "date",
      precision: 3,
    }).notNull(),
    resultKind: meterResultKindEnum("result_kind"),
    createdAt: timestamp("created_at", { withTimezone: true, mode: "date", precision: 3 })
      .notNull()
      .defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true, mode: "date", precision: 3 })
      .notNull()
      .defaultNow(),
  },
  (table) => [
    uniqueIndex("meter_operations_owner_client_unique").on(
      table.ownerId,
      table.clientRequestId,
    ),
    uniqueIndex("meter_operations_one_running_owner")
      .on(table.ownerId)
      .where(sql`${table.state} = 'running'`),
    index("meter_operations_owner_created_idx").on(table.ownerId, table.createdAt.desc()),
    check(
      "meter_operations_nonnegative",
      sql`${table.reservedCredits} >= 0 and ${table.chargedCredits} >= 0`,
    ),
    check(
      "meter_operations_charge_within_reservation",
      sql`${table.chargedCredits} <= ${table.reservedCredits}`,
    ),
  ],
);

export const llmCallUsage = pgTable(
  "llm_call_usage",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    operationId: uuid("operation_id").references(() => meterOperations.id, {
      onDelete: "set null",
    }),
    ownerId: uuid("owner_id").references(() => users.id, { onDelete: "set null" }),
    callKind: llmCallKindEnum("call_kind").notNull(),
    attempt: integer("attempt").notNull(),
    requestedModel: text("requested_model").notNull(),
    returnedModel: text("returned_model").notNull(),
    providerRequestId: text("provider_request_id"),
    status: llmCallStatusEnum("status").notNull(),
    promptTokens: integer("prompt_tokens").notNull(),
    cachedTokens: integer("cached_tokens").notNull(),
    cacheHitTokens: integer("cache_hit_tokens").notNull(),
    cacheMissTokens: integer("cache_miss_tokens").notNull(),
    completionTokens: integer("completion_tokens").notNull(),
    thinkingTokens: integer("thinking_tokens").notNull(),
    toolTokens: integer("tool_tokens").notNull(),
    usageSource: usageSourceEnum("usage_source").notNull(),
    rateVersion: text("rate_version").notNull(),
    companyCostNanoUsd: bigint("company_cost_nano_usd", { mode: "bigint" }).notNull(),
    createdAt: timestamp("created_at", { withTimezone: true, mode: "date", precision: 3 })
      .notNull()
      .defaultNow(),
  },
  (table) => [
    index("llm_call_usage_operation_idx").on(table.operationId),
    index("llm_call_usage_owner_created_idx").on(table.ownerId, table.createdAt.desc()),
    check("llm_call_usage_attempt_positive", sql`${table.attempt} > 0`),
    check(
      "llm_call_usage_tokens_nonnegative",
      sql`
        ${table.promptTokens} >= 0
        and ${table.cachedTokens} >= 0
        and ${table.cacheHitTokens} >= 0
        and ${table.cacheMissTokens} >= 0
        and ${table.completionTokens} >= 0
        and ${table.thinkingTokens} >= 0
        and ${table.toolTokens} >= 0
        and ${table.companyCostNanoUsd} >= 0
      `,
    ),
  ],
);

export const dailyUsage = pgTable(
  "daily_usage",
  {
    ownerId: uuid("owner_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    usageDate: date("usage_date", { mode: "string" }).notNull(),
    operationCount: integer("operation_count").notNull().default(0),
    providerCallCount: integer("provider_call_count").notNull().default(0),
    updatedAt: timestamp("updated_at", { withTimezone: true, mode: "date" }).notNull().defaultNow(),
  },
  (table) => [
    primaryKey({ columns: [table.ownerId, table.usageDate] }),
    check(
      "daily_usage_nonnegative",
      sql`${table.operationCount} >= 0 and ${table.providerCallCount} >= 0`,
    ),
  ],
);

export const creditAdjustments = pgTable(
  "credit_adjustments",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    ownerId: uuid("owner_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    periodId: uuid("period_id")
      .notNull()
      .references(() => usagePeriods.id, { onDelete: "restrict" }),
    deltaCredits: integer("delta_credits").notNull(),
    reasonCode: text("reason_code").notNull(),
    operatorRef: text("operator_ref"),
    createdAt: timestamp("created_at", { withTimezone: true, mode: "date", precision: 3 })
      .notNull()
      .defaultNow(),
  },
  (table) => [
    index("credit_adjustments_owner_created_idx").on(table.ownerId, table.createdAt.desc()),
    check("credit_adjustments_nonzero", sql`${table.deltaCredits} <> 0`),
  ],
);

export const tasteUsage = pgTable("taste_usage", {
  ownerId: uuid("owner_id")
    .primaryKey()
    .references(() => users.id, { onDelete: "cascade" }),
  clientTurnCount: integer("client_turn_count").notNull().default(0),
  readyCount: integer("ready_count").notNull().default(0),
  updatedAt: timestamp("updated_at", { withTimezone: true, mode: "date" }).notNull().defaultNow(),
});

export const cards = pgTable(
  "cards",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id),
    thoughtEn: text("thought_en").notNull(),
    thoughtOriginal: text("thought_original"),
    inputLanguage: text("input_language").notNull(),
    category: categoryEnum("category").notNull(),
    proposedCategory: text("proposed_category"),
    proposedLabel: text("proposed_label"),
    intensity: integer("intensity").notNull(),
    intensityBand: intensityBandEnum("intensity_band").notNull(),
    timeframe: timeframeEnum("timeframe").notNull(),
    safety: safetyFlagEnum("safety").notNull(),
    emotions: emotionEnum("emotions").array().notNull(),
    skippedStyles: jsonb("skipped_styles").$type<SkippedStyle[]>().notNull(),
    model: text("model").notNull(),
    spotlightStyle: styleEnum("spotlight_style").notNull(),
    isPublic: boolean("is_public").notNull().default(false),
    // Millisecond precision so the `createdAt|id` page cursor round-trips through a JS Date exactly.
    createdAt: timestamp("created_at", { withTimezone: true, mode: "date", precision: 3 })
      .notNull()
      .defaultNow(),
  },
  (table) => [
    // NULLS FIRST matches the default of `ORDER BY ... DESC`, so the planner can walk these in order.
    index("cards_user_created_idx").on(
      table.userId,
      table.createdAt.desc().nullsFirst(),
      table.id.desc().nullsFirst(),
    ),
    index("cards_category_idx").on(table.category),
    index("cards_public_created_idx")
      .on(table.createdAt.desc().nullsFirst(), table.id.desc().nullsFirst())
      .where(sql`${table.isPublic} = true`),
    index("cards_public_model_created_idx")
      .on(table.model, table.createdAt.desc().nullsFirst(), table.id.desc().nullsFirst())
      .where(sql`${table.isPublic} = true`),
    index("cards_emotions_gin_idx").using("gin", table.emotions),
    check("cards_intensity_range", sql`intensity between 1 and 5`),
  ],
);

export const cardReframes = pgTable(
  "card_reframes",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    cardId: uuid("card_id")
      .notNull()
      .references(() => cards.id, { onDelete: "cascade" }),
    style: styleEnum("style").notNull(),
    reframe: text("reframe").notNull(),
    position: integer("position").notNull(),
    isFavorite: boolean("is_favorite").notNull().default(false),
    favoritedAt: timestamp("favorited_at", { withTimezone: true, mode: "date" }),
  },
  (table) => [uniqueIndex("card_reframes_card_style_idx").on(table.cardId, table.style)],
);

export const tags = pgTable("tags", {
  id: uuid("id").primaryKey().defaultRandom(),
  slug: text("slug").notNull().unique(),
  label: text("label").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true, mode: "date" }).notNull().defaultNow(),
});

export const cardTags = pgTable(
  "card_tags",
  {
    cardId: uuid("card_id")
      .notNull()
      .references(() => cards.id, { onDelete: "cascade" }),
    tagId: uuid("tag_id")
      .notNull()
      .references(() => tags.id, { onDelete: "cascade" }),
  },
  (table) => [
    primaryKey({ columns: [table.cardId, table.tagId] }),
    index("card_tags_tag_id_idx").on(table.tagId),
  ],
);

export const savedAngles = pgTable(
  "saved_angles",
  {
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    cardId: uuid("card_id")
      .notNull()
      .references(() => cards.id, { onDelete: "cascade" }),
    style: styleEnum("style").notNull(),
    favoritedAt: timestamp("favorited_at", { withTimezone: true, mode: "date" })
      .notNull()
      .defaultNow(),
  },
  (table) => [
    primaryKey({ columns: [table.userId, table.cardId, table.style] }),
    index("saved_angles_user_favorited_idx").on(table.userId, table.favoritedAt.desc()),
  ],
);

export const follows = pgTable(
  "follows",
  {
    followerId: uuid("follower_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    followeeId: uuid("followee_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    createdAt: timestamp("created_at", { withTimezone: true, mode: "date" }).notNull().defaultNow(),
  },
  (table) => [
    primaryKey({ columns: [table.followerId, table.followeeId] }),
    index("follows_followee_idx").on(table.followeeId),
    check("follows_not_self", sql`${table.followerId} <> ${table.followeeId}`),
  ],
);

export const userBlocks = pgTable(
  "user_blocks",
  {
    blockerId: uuid("blocker_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    blockedId: uuid("blocked_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    createdAt: timestamp("created_at", { withTimezone: true, mode: "date" }).notNull().defaultNow(),
  },
  (table) => [
    primaryKey({ columns: [table.blockerId, table.blockedId] }),
    index("user_blocks_blocked_idx").on(table.blockedId),
    check("user_blocks_not_self", sql`${table.blockerId} <> ${table.blockedId}`),
  ],
);

export const cardReports = pgTable(
  "card_reports",
  {
    reporterId: uuid("reporter_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    cardId: uuid("card_id")
      .notNull()
      .references(() => cards.id, { onDelete: "cascade" }),
    reason: reportReasonEnum("reason").notNull(),
    createdAt: timestamp("created_at", { withTimezone: true, mode: "date" }).notNull().defaultNow(),
  },
  (table) => [
    primaryKey({ columns: [table.reporterId, table.cardId] }),
    index("card_reports_card_idx").on(table.cardId),
  ],
);

export const categoryProposals = pgTable("category_proposals", {
  slug: text("slug").primaryKey(),
  label: text("label").notNull(),
  seenCount: integer("seen_count").notNull().default(0),
  firstSeenAt: timestamp("first_seen_at", { withTimezone: true, mode: "date" })
    .notNull()
    .defaultNow(),
  lastSeenAt: timestamp("last_seen_at", { withTimezone: true, mode: "date" }).notNull().defaultNow(),
});

export const usersRelations = relations(users, ({ many }) => ({
  cards: many(cards),
  savedAngles: many(savedAngles),
  following: many(follows, { relationName: "following" }),
  followers: many(follows, { relationName: "followers" }),
  subscriptionEvents: many(subscriptionEvents),
}));

export const cardsRelations = relations(cards, ({ many, one }) => ({
  user: one(users, { fields: [cards.userId], references: [users.id] }),
  reframes: many(cardReframes),
  cardTags: many(cardTags),
  savedAngles: many(savedAngles),
}));

export const savedAnglesRelations = relations(savedAngles, ({ one }) => ({
  user: one(users, { fields: [savedAngles.userId], references: [users.id] }),
  card: one(cards, { fields: [savedAngles.cardId], references: [cards.id] }),
}));

export const followsRelations = relations(follows, ({ one }) => ({
  follower: one(users, {
    fields: [follows.followerId],
    references: [users.id],
    relationName: "following",
  }),
  followee: one(users, {
    fields: [follows.followeeId],
    references: [users.id],
    relationName: "followers",
  }),
}));

export const cardReframesRelations = relations(cardReframes, ({ one }) => ({
  card: one(cards, { fields: [cardReframes.cardId], references: [cards.id] }),
}));

export const tagsRelations = relations(tags, ({ many }) => ({
  cardTags: many(cardTags),
}));

export const cardTagsRelations = relations(cardTags, ({ one }) => ({
  card: one(cards, { fields: [cardTags.cardId], references: [cards.id] }),
  tag: one(tags, { fields: [cardTags.tagId], references: [tags.id] }),
}));

export type CardRow = typeof cards.$inferSelect;
export type CardReframeRow = typeof cardReframes.$inferSelect;
export type TagRow = typeof tags.$inferSelect;
export type UserRow = typeof users.$inferSelect;
