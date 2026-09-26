-- The dev-auth stand-in is gone: its accounts moved into Better Auth in 0003.
DROP TABLE "dev_auth_sessions" CASCADE;--> statement-breakpoint
DROP TABLE "dev_auth_users" CASCADE;