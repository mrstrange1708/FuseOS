import { sql } from 'drizzle-orm';
import {
  boolean,
  check,
  index,
  integer,
  pgTable,
  text,
  timestamp,
  uuid,
} from 'drizzle-orm/pg-core';

/**
 * Identity, owned by Better Auth (see auth/auth.ts and docs/schema.md). Column names and
 * nullability follow Better Auth's core schema; ids are UUIDs (`generateId: 'uuid'`) so
 * the migrated dev accounts keep theirs. We add the constraints Better Auth does not
 * declare itself — the "never let bad data in" rule applies to its tables too.
 */
export const user = pgTable(
  'user',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    name: text('name').notNull(),
    email: text('email').notNull().unique(),
    emailVerified: boolean('email_verified').notNull().default(false),
    image: text('image'),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [
    check('user_name_len', sql`length(${table.name}) between 1 and 100`),
    // Better Auth lower-cases emails; a mixed-case row would be a second account.
    check('user_email_lower', sql`${table.email} = lower(${table.email})`),
  ],
);

export const session = pgTable(
  'session',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    token: text('token').notNull().unique(),
    userId: uuid('user_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
    ipAddress: text('ip_address'),
    userAgent: text('user_agent'),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [index('session_user_id_idx').on(table.userId)],
);

/** Credentials. For email/password, `provider_id = 'credential'` and `password` is the hash. */
export const account = pgTable(
  'account',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    accountId: text('account_id').notNull(),
    providerId: text('provider_id').notNull(),
    userId: uuid('user_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
    accessToken: text('access_token'),
    refreshToken: text('refresh_token'),
    idToken: text('id_token'),
    accessTokenExpiresAt: timestamp('access_token_expires_at', { withTimezone: true }),
    refreshTokenExpiresAt: timestamp('refresh_token_expires_at', { withTimezone: true }),
    scope: text('scope'),
    password: text('password'),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [index('account_user_id_idx').on(table.userId)],
);

/** Short-lived values (email verification, password reset). */
export const verification = pgTable('verification', {
  id: uuid('id').primaryKey().defaultRandom(),
  identifier: text('identifier').notNull(),
  value: text('value').notNull(),
  expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
});

/** One row per registered device. `battery`/`last_seen` are updated over `/signal`. */
export const devices = pgTable(
  'devices',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id')
      .notNull()
      .references(() => user.id, { onDelete: 'cascade' }),
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

export type Device = typeof devices.$inferSelect;
