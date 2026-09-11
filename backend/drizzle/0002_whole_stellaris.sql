CREATE TABLE "saved_angles" (
	"user_id" uuid NOT NULL,
	"card_id" uuid NOT NULL,
	"style" "style" NOT NULL,
	"favorited_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "saved_angles_user_id_card_id_style_pk" PRIMARY KEY("user_id","card_id","style")
);
--> statement-breakpoint
CREATE TABLE "saved_pins" (
	"user_id" uuid NOT NULL,
	"card_id" uuid NOT NULL,
	"pinned_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "saved_pins_user_id_card_id_pk" PRIMARY KEY("user_id","card_id")
);
--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "initials" text;--> statement-breakpoint
UPDATE "users" SET "initials" = 'JM' WHERE "initials" IS NULL;--> statement-breakpoint
ALTER TABLE "users" ALTER COLUMN "initials" SET NOT NULL;--> statement-breakpoint
ALTER TABLE "saved_angles" ADD CONSTRAINT "saved_angles_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "saved_angles" ADD CONSTRAINT "saved_angles_card_id_cards_id_fk" FOREIGN KEY ("card_id") REFERENCES "public"."cards"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "saved_pins" ADD CONSTRAINT "saved_pins_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "saved_pins" ADD CONSTRAINT "saved_pins_card_id_cards_id_fk" FOREIGN KEY ("card_id") REFERENCES "public"."cards"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "saved_angles_user_favorited_idx" ON "saved_angles" USING btree ("user_id","favorited_at" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX "saved_pins_user_pinned_idx" ON "saved_pins" USING btree ("user_id","pinned_at" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX "cards_public_created_idx" ON "cards" USING btree ("is_public","created_at" DESC NULLS LAST);--> statement-breakpoint
ALTER TABLE "users" ADD CONSTRAINT "users_initials_len" CHECK (char_length(initials) = 2);