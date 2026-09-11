ALTER TABLE "card_reframes" ADD COLUMN "is_favorite" boolean DEFAULT false NOT NULL;--> statement-breakpoint
ALTER TABLE "card_reframes" ADD COLUMN "favorited_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "cards" ADD COLUMN "is_pinned" boolean DEFAULT false NOT NULL;--> statement-breakpoint
ALTER TABLE "cards" ADD COLUMN "pinned_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "cards" ADD COLUMN "is_public" boolean DEFAULT false NOT NULL;--> statement-breakpoint
CREATE INDEX "cards_user_pinned_idx" ON "cards" USING btree ("user_id","pinned_at" DESC NULLS LAST);--> statement-breakpoint
UPDATE "card_reframes" AS r
SET "is_favorite" = c."is_favorite",
    "favorited_at" = c."favorited_at"
FROM "cards" AS c
WHERE r."card_id" = c."id"
  AND c."is_favorite" = true;--> statement-breakpoint
ALTER TABLE "cards" DROP COLUMN "is_favorite";--> statement-breakpoint
ALTER TABLE "cards" DROP COLUMN "favorited_at";
