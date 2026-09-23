ALTER TABLE "users" DROP CONSTRAINT "users_initials_len";--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "avatar_key" text;--> statement-breakpoint
ALTER TABLE "users" ADD CONSTRAINT "users_initials_len" CHECK (char_length(initials) between 1 and 2);