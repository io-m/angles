CREATE TABLE "card_decisions" (
	"user_id" uuid NOT NULL,
	"card_id" uuid NOT NULL,
	"kind" "decision_kind" NOT NULL,
	"style" "style" NOT NULL,
	"checked_styles" "style"[] NOT NULL,
	"passes" smallint DEFAULT 0 NOT NULL,
	"decided_at" timestamp (3) with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "card_decisions_user_id_card_id_pk" PRIMARY KEY("user_id","card_id"),
	CONSTRAINT "card_decisions_passes_range" CHECK ("card_decisions"."passes" between 0 and 2),
	CONSTRAINT "card_decisions_pass_counted" CHECK ("card_decisions"."kind" <> 'pass' or "card_decisions"."passes" >= 1),
	CONSTRAINT "card_decisions_style_checked" CHECK ("card_decisions"."style" = any("card_decisions"."checked_styles"))
);
--> statement-breakpoint
ALTER TABLE "card_decisions" ADD CONSTRAINT "card_decisions_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "card_decisions" ADD CONSTRAINT "card_decisions_card_id_cards_id_fk" FOREIGN KEY ("card_id") REFERENCES "public"."cards"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "card_decisions_user_kind_decided_idx" ON "card_decisions" USING btree ("user_id","kind","decided_at" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX "card_decisions_card_saves_idx" ON "card_decisions" USING btree ("card_id") WHERE "card_decisions"."kind" = 'save';--> statement-breakpoint
CREATE UNIQUE INDEX "users_one_house_idx" ON "users" USING btree ("kind") WHERE "users"."kind" = 'house';