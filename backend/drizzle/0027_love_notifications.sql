CREATE TABLE "love_notifications" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"recipient_id" uuid NOT NULL,
	"actor_id" uuid NOT NULL,
	"card_id" uuid NOT NULL,
	"style" "style" NOT NULL,
	"created_at" timestamp (3) with time zone DEFAULT now() NOT NULL,
	"read_at" timestamp with time zone,
	"pushed_at" timestamp with time zone
);
--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "notify_loves" boolean DEFAULT true NOT NULL;--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "share_love_name" boolean DEFAULT true NOT NULL;--> statement-breakpoint
ALTER TABLE "love_notifications" ADD CONSTRAINT "love_notifications_recipient_id_users_id_fk" FOREIGN KEY ("recipient_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "love_notifications" ADD CONSTRAINT "love_notifications_actor_id_users_id_fk" FOREIGN KEY ("actor_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "love_notifications" ADD CONSTRAINT "love_notifications_card_id_cards_id_fk" FOREIGN KEY ("card_id") REFERENCES "public"."cards"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "love_notifications_recipient_created_idx" ON "love_notifications" USING btree ("recipient_id","created_at" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX "love_notifications_card_idx" ON "love_notifications" USING btree ("card_id");--> statement-breakpoint
CREATE UNIQUE INDEX "love_notifications_unread_idx" ON "love_notifications" USING btree ("recipient_id","actor_id","card_id") WHERE "love_notifications"."read_at" is null;--> statement-breakpoint
CREATE INDEX "love_notifications_unpushed_idx" ON "love_notifications" USING btree ("created_at") WHERE "love_notifications"."pushed_at" is null;--> statement-breakpoint
CREATE INDEX "card_decisions_card_idx" ON "card_decisions" USING btree ("card_id","decided_at");