import { sql } from 'drizzle-orm';
import { check, index, integer, pgTable, text, timestamp, uuid } from 'drizzle-orm/pg-core';

/**
 * DEV-ONLY credentials store for the `dev-auth` stand-in (see auth/dev-auth.ts).
 *
 * The real identity schema is owned by Better Auth (tables `user`, `account`,
 * `session`, …) — see docs/schema.md. These `dev_auth_*` tables exist only so the
 * dev login persists across server restarts while Better Auth is not yet wired,
 * and are meant to be dropped when it lands. The `devices` table below
 * follows docs/schema.md but references `dev_auth_users` for the same reason; its
 * FK target moves to the Better Auth user id later. Integrity is enforced in the
 * schema itself (NOT NULL, UNIQUE, CHECK) per the "never let bad data in" rule.
 */
export const devAuthUsers = pgTable(
  'dev_auth_users',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    email: text('email').notNull().unique(),
    name: text('name').notNull(),
    passwordSalt: text('password_salt').notNull(),
    passwordHash: text('password_hash').notNull(),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [check('dev_auth_users_name_len', sql`length(${table.name}) between 1 and 100`)],
);

/** Opaque bearer tokens issued at sign-in, mapped to a user. Dev stand-in for JWT. */
export const devAuthSessions = pgTable('dev_auth_sessions', {
  token: text('token').primaryKey(),
  userId: uuid('user_id')
    .notNull()
    .references(() => devAuthUsers.id, { onDelete: 'cascade' }),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
});

/** One row per registered device. `battery`/`last_seen` are updated over `/signal`. */
export const devices = pgTable(
  'devices',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id')
      .notNull()
      .references(() => devAuthUsers.id, { onDelete: 'cascade' }),
    name: text('name').notNull(),
    platform: text('platform').notNull(),
    publicKey: text('public_key').notNull().unique(),
    // Operational presence metadata (never a user payload): 0–100, null until reported.
    battery: integer('battery'),
    lastSeen: timestamp('last_seen', { withTimezone: true }),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [
    check('devices_name_len', sql`length(${table.name}) between 1 and 100`),
    check('devices_platform', sql`${table.platform} in ('android','macos')`),
    check(
      'devices_battery_range',
      sql`${table.battery} is null or ${table.battery} between 0 and 100`,
    ),
    index('devices_user_id_idx').on(table.userId),
  ],
);

/**
 * There is no pairing/trust table: two devices are trusted because they are on the same
 * account (see devices/trust.ts). `pairing_codes` and `device_trust` were dropped in
 * migration 0002 along with the code-entry flow they existed for.
 */

export type DevAuthUser = typeof devAuthUsers.$inferSelect;
export type Device = typeof devices.$inferSelect;
