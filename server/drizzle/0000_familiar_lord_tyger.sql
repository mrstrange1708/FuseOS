CREATE TABLE "dev_auth_users" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"email" text NOT NULL,
	"name" text NOT NULL,
	"password_salt" text NOT NULL,
	"password_hash" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "dev_auth_users_email_unique" UNIQUE("email"),
	CONSTRAINT "dev_auth_users_name_len" CHECK (length("dev_auth_users"."name") between 1 and 100)
);
