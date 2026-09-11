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
    initials: text("initials").notNull(),
    createdAt: timestamp("created_at", { withTimezone: true, mode: "date" }).notNull().defaultNow(),
  },
  (table) => [check("users_initials_len", sql`char_length(initials) = 2`)],
);

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
    isPinned: boolean("is_pinned").notNull().default(false),
    pinnedAt: timestamp("pinned_at", { withTimezone: true, mode: "date" }),
    isPublic: boolean("is_public").notNull().default(false),
    createdAt: timestamp("created_at", { withTimezone: true, mode: "date" }).notNull().defaultNow(),
  },
  (table) => [
    index("cards_user_created_idx").on(table.userId, table.createdAt.desc()),
    index("cards_category_idx").on(table.category),
    index("cards_user_pinned_idx").on(table.userId, table.pinnedAt.desc()),
    index("cards_public_created_idx").on(table.isPublic, table.createdAt.desc()),
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

export const savedPins = pgTable(
  "saved_pins",
  {
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    cardId: uuid("card_id")
      .notNull()
      .references(() => cards.id, { onDelete: "cascade" }),
    pinnedAt: timestamp("pinned_at", { withTimezone: true, mode: "date" }).notNull().defaultNow(),
  },
  (table) => [
    primaryKey({ columns: [table.userId, table.cardId] }),
    index("saved_pins_user_pinned_idx").on(table.userId, table.pinnedAt.desc()),
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
  savedPins: many(savedPins),
  savedAngles: many(savedAngles),
}));

export const cardsRelations = relations(cards, ({ many, one }) => ({
  user: one(users, { fields: [cards.userId], references: [users.id] }),
  reframes: many(cardReframes),
  cardTags: many(cardTags),
  savedPins: many(savedPins),
  savedAngles: many(savedAngles),
}));

export const savedPinsRelations = relations(savedPins, ({ one }) => ({
  user: one(users, { fields: [savedPins.userId], references: [users.id] }),
  card: one(cards, { fields: [savedPins.cardId], references: [cards.id] }),
}));

export const savedAnglesRelations = relations(savedAngles, ({ one }) => ({
  user: one(users, { fields: [savedAngles.userId], references: [users.id] }),
  card: one(cards, { fields: [savedAngles.cardId], references: [cards.id] }),
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
