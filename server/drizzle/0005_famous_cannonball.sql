ALTER TABLE "devices" ADD COLUMN "install_id" text;--> statement-breakpoint
CREATE UNIQUE INDEX "devices_user_install_idx" ON "devices" USING btree ("user_id","install_id");--> statement-breakpoint
ALTER TABLE "devices" ADD CONSTRAINT "devices_install_id_len" CHECK ("devices"."install_id" is null or length("devices"."install_id") between 16 and 128);