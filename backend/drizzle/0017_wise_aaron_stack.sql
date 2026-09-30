ALTER TYPE "public"."llm_call_kind" ADD VALUE 'rewrite';--> statement-breakpoint
DROP INDEX "cards_public_model_created_idx";--> statement-breakpoint
ALTER TABLE "card_reframes" ADD COLUMN "reframe_original" text;