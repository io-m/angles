CREATE TYPE "public"."category" AS ENUM('work', 'money', 'romantic', 'family', 'friends_social', 'health', 'self_worth', 'future', 'grief_loss', 'identity', 'other');--> statement-breakpoint
CREATE TYPE "public"."emotion" AS ENUM('anger', 'shame', 'fear', 'sadness', 'envy', 'loneliness', 'overwhelm', 'numbness', 'hope');--> statement-breakpoint
CREATE TYPE "public"."intensity_band" AS ENUM('low', 'mid', 'high');--> statement-breakpoint
CREATE TYPE "public"."safety_flag" AS ENUM('none', 'self_harm', 'harm_others', 'abuse');--> statement-breakpoint
CREATE TYPE "public"."style" AS ENUM('stoic', 'optimistic', 'humorous', 'tough_love');--> statement-breakpoint
CREATE TYPE "public"."timeframe" AS ENUM('past', 'ongoing', 'future');--> statement-breakpoint
CREATE TABLE "card_reframes" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"card_id" uuid NOT NULL,
	"style" "style" NOT NULL,
	"reframe" text NOT NULL,
	"position" integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE "card_tags" (
	"card_id" uuid NOT NULL,
	"tag_id" uuid NOT NULL,
	CONSTRAINT "card_tags_card_id_tag_id_pk" PRIMARY KEY("card_id","tag_id")
);
--> statement-breakpoint
CREATE TABLE "cards" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"thought_en" text NOT NULL,
	"thought_original" text,
	"input_language" text NOT NULL,
	"category" "category" NOT NULL,
	"proposed_category" text,
	"proposed_label" text,
	"intensity" integer NOT NULL,
	"intensity_band" "intensity_band" NOT NULL,
	"timeframe" timeframe NOT NULL,
	"safety" "safety_flag" NOT NULL,
	"emotions" "emotion"[] NOT NULL,
	"skipped_styles" jsonb NOT NULL,
	"model" text NOT NULL,
	"spotlight_style" "style" NOT NULL,
	"is_favorite" boolean DEFAULT false NOT NULL,
	"favorited_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "cards_intensity_range" CHECK (intensity between 1 and 5)
);
--> statement-breakpoint
CREATE TABLE "category_proposals" (
	"slug" text PRIMARY KEY NOT NULL,
	"label" text NOT NULL,
	"seen_count" integer DEFAULT 0 NOT NULL,
	"first_seen_at" timestamp with time zone DEFAULT now() NOT NULL,
	"last_seen_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "tags" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"slug" text NOT NULL,
	"label" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "tags_slug_unique" UNIQUE("slug")
);
--> statement-breakpoint
CREATE TABLE "users" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "card_reframes" ADD CONSTRAINT "card_reframes_card_id_cards_id_fk" FOREIGN KEY ("card_id") REFERENCES "public"."cards"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "card_tags" ADD CONSTRAINT "card_tags_card_id_cards_id_fk" FOREIGN KEY ("card_id") REFERENCES "public"."cards"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "card_tags" ADD CONSTRAINT "card_tags_tag_id_tags_id_fk" FOREIGN KEY ("tag_id") REFERENCES "public"."tags"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "cards" ADD CONSTRAINT "cards_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "card_reframes_card_style_idx" ON "card_reframes" USING btree ("card_id","style");--> statement-breakpoint
CREATE INDEX "card_tags_tag_id_idx" ON "card_tags" USING btree ("tag_id");--> statement-breakpoint
CREATE INDEX "cards_user_created_idx" ON "cards" USING btree ("user_id","created_at" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX "cards_category_idx" ON "cards" USING btree ("category");--> statement-breakpoint
INSERT INTO "users" ("id") VALUES ('00000000-0000-4000-8000-000000000001');