CREATE TYPE "public"."subscription_environment" AS ENUM('sandbox', 'production');--> statement-breakpoint
CREATE TYPE "public"."subscription_status" AS ENUM('active', 'grace', 'billing_retry', 'expired', 'revoked');--> statement-breakpoint
CREATE TABLE "subscription_entitlements" (
	"user_id" uuid PRIMARY KEY NOT NULL,
	"original_transaction_id" text NOT NULL,
	"current_transaction_id" text NOT NULL,
	"product_id" text NOT NULL,
	"environment" "subscription_environment" NOT NULL,
	"status" "subscription_status" NOT NULL,
	"paid_through" timestamp with time zone NOT NULL,
	"revoked_at" timestamp with time zone,
	"quota_anchor" timestamp with time zone NOT NULL,
	"last_apple_event_at" timestamp (3) with time zone NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "subscription_entitlements_product_id" CHECK ("subscription_entitlements"."product_id" in ('app.angles.ios.annual', 'app.angles.ios.monthly'))
);
--> statement-breakpoint
CREATE TABLE "subscription_events" (
	"notification_uuid" uuid PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"notification_type" text NOT NULL,
	"subtype" text,
	"original_transaction_id" text NOT NULL,
	"transaction_id" text NOT NULL,
	"signed_at" timestamp (3) with time zone NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "subscription_entitlements" ADD CONSTRAINT "subscription_entitlements_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "subscription_events" ADD CONSTRAINT "subscription_events_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "subscription_entitlements_original_transaction_unique" ON "subscription_entitlements" USING btree ("original_transaction_id");--> statement-breakpoint
CREATE UNIQUE INDEX "subscription_entitlements_current_transaction_unique" ON "subscription_entitlements" USING btree ("current_transaction_id");--> statement-breakpoint
CREATE INDEX "subscription_entitlements_access_idx" ON "subscription_entitlements" USING btree ("user_id","status","paid_through");--> statement-breakpoint
CREATE UNIQUE INDEX "subscription_events_notification_metadata_unique" ON "subscription_events" USING btree ("notification_uuid","notification_type","subtype");--> statement-breakpoint
CREATE INDEX "subscription_events_user_signed_idx" ON "subscription_events" USING btree ("user_id","signed_at" DESC NULLS LAST);