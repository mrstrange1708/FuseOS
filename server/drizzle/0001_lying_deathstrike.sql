CREATE TABLE "dev_auth_sessions" (
	"token" text PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "device_trust" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"device_a" uuid NOT NULL,
	"device_b" uuid NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "device_trust_pair_uq" UNIQUE("device_a","device_b"),
	CONSTRAINT "device_trust_distinct" CHECK ("device_trust"."device_a" <> "device_trust"."device_b"),
	CONSTRAINT "device_trust_ordered" CHECK ("device_trust"."device_a" < "device_trust"."device_b")
);
--> statement-breakpoint
CREATE TABLE "devices" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"name" text NOT NULL,
	"platform" text NOT NULL,
	"public_key" text NOT NULL,
	"battery" integer,
	"last_seen" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "devices_public_key_unique" UNIQUE("public_key"),
	CONSTRAINT "devices_name_len" CHECK (length("devices"."name") between 1 and 100),
	CONSTRAINT "devices_platform" CHECK ("devices"."platform" in ('android','macos')),
	CONSTRAINT "devices_battery_range" CHECK ("devices"."battery" is null or "devices"."battery" between 0 and 100)
);
--> statement-breakpoint
CREATE TABLE "pairing_codes" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"device_id" uuid NOT NULL,
	"code" text NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"used_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "pairing_codes_code_len" CHECK (length("pairing_codes"."code") between 6 and 12),
	CONSTRAINT "pairing_codes_expiry" CHECK ("pairing_codes"."expires_at" > "pairing_codes"."created_at")
);
--> statement-breakpoint
ALTER TABLE "dev_auth_sessions" ADD CONSTRAINT "dev_auth_sessions_user_id_dev_auth_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."dev_auth_users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "device_trust" ADD CONSTRAINT "device_trust_device_a_devices_id_fk" FOREIGN KEY ("device_a") REFERENCES "public"."devices"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "device_trust" ADD CONSTRAINT "device_trust_device_b_devices_id_fk" FOREIGN KEY ("device_b") REFERENCES "public"."devices"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "devices" ADD CONSTRAINT "devices_user_id_dev_auth_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."dev_auth_users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "pairing_codes" ADD CONSTRAINT "pairing_codes_user_id_dev_auth_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."dev_auth_users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "pairing_codes" ADD CONSTRAINT "pairing_codes_device_id_devices_id_fk" FOREIGN KEY ("device_id") REFERENCES "public"."devices"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "devices_user_id_idx" ON "devices" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "pairing_codes_user_id_idx" ON "pairing_codes" USING btree ("user_id");--> statement-breakpoint
CREATE UNIQUE INDEX "pairing_codes_active_code_uq" ON "pairing_codes" USING btree ("code") WHERE "pairing_codes"."used_at" is null;