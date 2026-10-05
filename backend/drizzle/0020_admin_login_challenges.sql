CREATE TABLE "admin_login_challenges" (
	"jti" text PRIMARY KEY NOT NULL,
	"email" text NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"used_at" timestamp with time zone
);
--> statement-breakpoint
CREATE INDEX "admin_login_challenges_expires_idx" ON "admin_login_challenges" USING btree ("expires_at");