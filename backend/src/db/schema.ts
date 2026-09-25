import { relations, sql } from "drizzle-orm";
import {
  boolean,
  check,
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

export const styleEnum = pgEnum("style", [...STYLES]);
export const categoryEnum = pgEnum("category", [...CATEGORIES]);
export const emotionEnum = pgEnum("emotion", [...EMOTIONS]);
export const timeframeEnum = pgEnum("timeframe", [...TIMEFRAMES]);
export const safetyFlagEnum = pgEnum("safety_flag", [...SAFETY_FLAGS]);
export const intensityBandEnum = pgEnum("intensity_band", [...INTENSITY_BANDS]);

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
