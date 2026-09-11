ALTER TABLE "saved_pins" DISABLE ROW LEVEL SECURITY;--> statement-breakpoint
DROP TABLE "saved_pins" CASCADE;--> statement-breakpoint
DROP INDEX "cards_user_pinned_idx";--> statement-breakpoint
ALTER TABLE "cards" DROP COLUMN "is_pinned";--> statement-breakpoint
ALTER TABLE "cards" DROP COLUMN "pinned_at";