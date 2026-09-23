DROP INDEX "cards_user_created_idx";--> statement-breakpoint
DROP INDEX "cards_public_created_idx";--> statement-breakpoint
ALTER TABLE "cards" ALTER COLUMN "created_at" SET DATA TYPE timestamp (3) with time zone;--> statement-breakpoint
ALTER TABLE "cards" ALTER COLUMN "created_at" SET DEFAULT now();--> statement-breakpoint
CREATE INDEX "cards_user_created_idx" ON "cards" USING btree ("user_id","created_at" DESC NULLS FIRST,"id" DESC NULLS FIRST);--> statement-breakpoint
CREATE INDEX "cards_public_created_idx" ON "cards" USING btree ("created_at" DESC NULLS FIRST,"id" DESC NULLS FIRST) WHERE "cards"."is_public" = true;