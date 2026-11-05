CREATE TYPE "public"."decision_kind" AS ENUM('save', 'pass');--> statement-breakpoint
CREATE TYPE "public"."user_kind" AS ENUM('person', 'house');--> statement-breakpoint
DROP TABLE "saved_angles" CASCADE;--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "kind" "user_kind" DEFAULT 'person' NOT NULL;--> statement-breakpoint
ALTER TABLE "card_reframes" DROP COLUMN "is_hearted";--> statement-breakpoint
ALTER TABLE "card_reframes" DROP COLUMN "hearted_at";