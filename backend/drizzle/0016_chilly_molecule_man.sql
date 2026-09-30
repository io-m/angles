CREATE TABLE "reframe_replays" (
	"operation_id" uuid PRIMARY KEY NOT NULL,
	"owner_id" uuid NOT NULL,
	"iv" text NOT NULL,
	"auth_tag" text NOT NULL,
	"ciphertext" text NOT NULL,
	"expires_at" timestamp (3) with time zone NOT NULL
);
--> statement-breakpoint
ALTER TABLE "cards" DROP CONSTRAINT "cards_user_id_users_id_fk";
--> statement-breakpoint
ALTER TABLE "cards" ADD COLUMN "cook_signature" text;--> statement-breakpoint
ALTER TABLE "reframe_replays" ADD CONSTRAINT "reframe_replays_operation_id_meter_operations_id_fk" FOREIGN KEY ("operation_id") REFERENCES "public"."meter_operations"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "reframe_replays" ADD CONSTRAINT "reframe_replays_owner_id_users_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "reframe_replays_expires_idx" ON "reframe_replays" USING btree ("expires_at");--> statement-breakpoint
ALTER TABLE "cards" ADD CONSTRAINT "cards_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "cards_user_cook_signature_unique" ON "cards" USING btree ("user_id","cook_signature");