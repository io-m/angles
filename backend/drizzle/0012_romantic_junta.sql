CREATE TYPE "public"."llm_call_kind" AS ENUM('decision', 'batch', 'reframe', 'moderation');--> statement-breakpoint
CREATE TYPE "public"."llm_call_status" AS ENUM('succeeded', 'failed');--> statement-breakpoint
CREATE TYPE "public"."meter_operation_kind" AS ENUM('full', 'recook');--> statement-breakpoint
CREATE TYPE "public"."meter_operation_state" AS ENUM('running', 'ready', 'continue', 'failed', 'expired');--> statement-breakpoint
CREATE TYPE "public"."meter_result_kind" AS ENUM('ready', 'continue');--> statement-breakpoint
CREATE TYPE "public"."usage_source" AS ENUM('reported', 'estimated');--> statement-breakpoint
CREATE TABLE "credit_adjustments" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"owner_id" uuid NOT NULL,
	"period_id" uuid NOT NULL,
	"delta_credits" integer NOT NULL,
	"reason_code" text NOT NULL,
	"operator_ref" text,
	"created_at" timestamp (3) with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "credit_adjustments_nonzero" CHECK ("credit_adjustments"."delta_credits" <> 0)
);
--> statement-breakpoint
CREATE TABLE "daily_usage" (
	"owner_id" uuid NOT NULL,
	"usage_date" date NOT NULL,
	"operation_count" integer DEFAULT 0 NOT NULL,
	"provider_call_count" integer DEFAULT 0 NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "daily_usage_owner_id_usage_date_pk" PRIMARY KEY("owner_id","usage_date"),
	CONSTRAINT "daily_usage_nonnegative" CHECK ("daily_usage"."operation_count" >= 0 and "daily_usage"."provider_call_count" >= 0)
);
--> statement-breakpoint
CREATE TABLE "llm_call_usage" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"operation_id" uuid,
	"owner_id" uuid,
	"call_kind" "llm_call_kind" NOT NULL,
	"attempt" integer NOT NULL,
	"requested_model" text NOT NULL,
	"returned_model" text NOT NULL,
	"provider_request_id" text,
	"status" "llm_call_status" NOT NULL,
	"prompt_tokens" integer NOT NULL,
	"cached_tokens" integer NOT NULL,
	"cache_hit_tokens" integer NOT NULL,
	"cache_miss_tokens" integer NOT NULL,
	"completion_tokens" integer NOT NULL,
	"thinking_tokens" integer NOT NULL,
	"tool_tokens" integer NOT NULL,
	"usage_source" "usage_source" NOT NULL,
	"rate_version" text NOT NULL,
	"company_cost_nano_usd" bigint NOT NULL,
	"created_at" timestamp (3) with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "llm_call_usage_attempt_positive" CHECK ("llm_call_usage"."attempt" > 0),
	CONSTRAINT "llm_call_usage_tokens_nonnegative" CHECK (
        "llm_call_usage"."prompt_tokens" >= 0
        and "llm_call_usage"."cached_tokens" >= 0
        and "llm_call_usage"."cache_hit_tokens" >= 0
        and "llm_call_usage"."cache_miss_tokens" >= 0
        and "llm_call_usage"."completion_tokens" >= 0
        and "llm_call_usage"."thinking_tokens" >= 0
        and "llm_call_usage"."tool_tokens" >= 0
        and "llm_call_usage"."company_cost_nano_usd" >= 0
      )
);
--> statement-breakpoint
CREATE TABLE "meter_operations" (
	"id" uuid PRIMARY KEY NOT NULL,
	"owner_id" uuid NOT NULL,
	"client_request_id" uuid NOT NULL,
	"request_fingerprint" text NOT NULL,
	"period_id" uuid,
	"model" text NOT NULL,
	"kind" "meter_operation_kind" NOT NULL,
	"reserved_credits" integer DEFAULT 0 NOT NULL,
	"charged_credits" integer DEFAULT 0 NOT NULL,
	"state" "meter_operation_state" NOT NULL,
	"lease_expires_at" timestamp (3) with time zone NOT NULL,
	"result_kind" "meter_result_kind",
	"created_at" timestamp (3) with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp (3) with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "meter_operations_nonnegative" CHECK ("meter_operations"."reserved_credits" >= 0 and "meter_operations"."charged_credits" >= 0),
	CONSTRAINT "meter_operations_charge_within_reservation" CHECK ("meter_operations"."charged_credits" <= "meter_operations"."reserved_credits")
);
--> statement-breakpoint
CREATE TABLE "taste_usage" (
	"owner_id" uuid PRIMARY KEY NOT NULL,
	"client_turn_count" integer DEFAULT 0 NOT NULL,
	"ready_count" integer DEFAULT 0 NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "usage_periods" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"owner_id" uuid NOT NULL,
	"entitlement_user_id" uuid,
	"starts_at" timestamp (3) with time zone NOT NULL,
	"ends_at" timestamp (3) with time zone NOT NULL,
	"granted_credits" integer NOT NULL,
	"reserved_credits" integer DEFAULT 0 NOT NULL,
	"charged_credits" integer DEFAULT 0 NOT NULL,
	"plan_version" text NOT NULL,
	"tariff_version" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "usage_periods_nonnegative" CHECK (
      "usage_periods"."granted_credits" >= 0
      and "usage_periods"."reserved_credits" >= 0
      and "usage_periods"."charged_credits" >= 0
    ),
	CONSTRAINT "usage_periods_within_grant" CHECK ("usage_periods"."reserved_credits" + "usage_periods"."charged_credits" <= "usage_periods"."granted_credits"),
	CONSTRAINT "usage_periods_valid_range" CHECK ("usage_periods"."ends_at" > "usage_periods"."starts_at")
);
--> statement-breakpoint
ALTER TABLE "credit_adjustments" ADD CONSTRAINT "credit_adjustments_owner_id_users_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "credit_adjustments" ADD CONSTRAINT "credit_adjustments_period_id_usage_periods_id_fk" FOREIGN KEY ("period_id") REFERENCES "public"."usage_periods"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "daily_usage" ADD CONSTRAINT "daily_usage_owner_id_users_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "llm_call_usage" ADD CONSTRAINT "llm_call_usage_operation_id_meter_operations_id_fk" FOREIGN KEY ("operation_id") REFERENCES "public"."meter_operations"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "llm_call_usage" ADD CONSTRAINT "llm_call_usage_owner_id_users_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."users"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "meter_operations" ADD CONSTRAINT "meter_operations_owner_id_users_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "meter_operations" ADD CONSTRAINT "meter_operations_period_id_usage_periods_id_fk" FOREIGN KEY ("period_id") REFERENCES "public"."usage_periods"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "taste_usage" ADD CONSTRAINT "taste_usage_owner_id_users_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "usage_periods" ADD CONSTRAINT "usage_periods_owner_id_users_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "usage_periods" ADD CONSTRAINT "usage_periods_entitlement_user_id_subscription_entitlements_user_id_fk" FOREIGN KEY ("entitlement_user_id") REFERENCES "public"."subscription_entitlements"("user_id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "credit_adjustments_owner_created_idx" ON "credit_adjustments" USING btree ("owner_id","created_at" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX "llm_call_usage_operation_idx" ON "llm_call_usage" USING btree ("operation_id");--> statement-breakpoint
CREATE INDEX "llm_call_usage_owner_created_idx" ON "llm_call_usage" USING btree ("owner_id","created_at" DESC NULLS LAST);--> statement-breakpoint
CREATE UNIQUE INDEX "meter_operations_owner_client_unique" ON "meter_operations" USING btree ("owner_id","client_request_id");--> statement-breakpoint
CREATE UNIQUE INDEX "meter_operations_one_running_owner" ON "meter_operations" USING btree ("owner_id") WHERE "meter_operations"."state" = 'running';--> statement-breakpoint
CREATE INDEX "meter_operations_owner_created_idx" ON "meter_operations" USING btree ("owner_id","created_at" DESC NULLS LAST);--> statement-breakpoint
CREATE UNIQUE INDEX "usage_periods_owner_start_unique" ON "usage_periods" USING btree ("owner_id","starts_at");--> statement-breakpoint
CREATE INDEX "usage_periods_owner_ends_idx" ON "usage_periods" USING btree ("owner_id","ends_at");