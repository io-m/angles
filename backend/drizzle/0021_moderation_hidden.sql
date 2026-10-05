ALTER TABLE "cards" ADD COLUMN "moderation_hidden_at" timestamp with time zone;
--> statement-breakpoint
UPDATE "cards" AS c
SET "moderation_hidden_at" = r.hidden_at
FROM (
  SELECT "card_id", max("reviewed_at") AS hidden_at
  FROM "card_reports"
  WHERE "resolution" = 'hidden'
  GROUP BY "card_id"
) AS r
WHERE c."id" = r."card_id";
