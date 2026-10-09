ALTER TYPE "public"."style" RENAME VALUE 'optimistic' TO 'hopeful';--> statement-breakpoint
ALTER TYPE "public"."style" RENAME VALUE 'humorous' TO 'witty';--> statement-breakpoint
ALTER TYPE "public"."style" RENAME VALUE 'tough_love' TO 'tough';--> statement-breakpoint
ALTER TABLE "card_reframes" RENAME COLUMN "is_favorite" TO "is_hearted";--> statement-breakpoint
ALTER TABLE "card_reframes" RENAME COLUMN "favorited_at" TO "hearted_at";--> statement-breakpoint
ALTER TABLE "saved_angles" RENAME COLUMN "favorited_at" TO "hearted_at";--> statement-breakpoint
ALTER INDEX "saved_angles_user_favorited_idx" RENAME TO "saved_angles_user_hearted_idx";--> statement-breakpoint
UPDATE "cards"
SET "skipped_styles" = (
  SELECT COALESCE(
    jsonb_agg(
      CASE e.item ->> 'style'
        WHEN 'optimistic' THEN jsonb_set(e.item, '{style}', '"hopeful"')
        WHEN 'humorous' THEN jsonb_set(e.item, '{style}', '"witty"')
        WHEN 'tough_love' THEN jsonb_set(e.item, '{style}', '"tough"')
        ELSE e.item
      END
      ORDER BY e.ord
    ),
    '[]'::jsonb
  )
  FROM jsonb_array_elements("cards"."skipped_styles") WITH ORDINALITY AS e(item, ord)
)
WHERE "skipped_styles" <> '[]'::jsonb;
