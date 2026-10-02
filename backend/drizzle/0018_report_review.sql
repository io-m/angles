CREATE TYPE "public"."report_resolution" AS ENUM('kept', 'hidden');--> statement-breakpoint
ALTER TABLE "card_reports" ADD COLUMN "reviewed_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "card_reports" ADD COLUMN "resolution" "report_resolution";--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "publishing_suspended_at" timestamp with time zone;--> statement-breakpoint
CREATE INDEX "card_reports_pending_idx" ON "card_reports" USING btree ("created_at") WHERE "card_reports"."reviewed_at" is null;--> statement-breakpoint
ALTER TABLE "card_reports" ADD CONSTRAINT "card_reports_review_pair" CHECK (("card_reports"."reviewed_at" is null) = ("card_reports"."resolution" is null));