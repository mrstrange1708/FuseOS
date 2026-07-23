import { sql } from 'drizzle-orm';
import {
  check,
  index,
  integer,
  pgTable,
  text,
  timestamp,
  unique,
  uniqueIndex,
  uuid,
} from 'drizzle-orm/pg-core';

/**
 * DEV-ONLY credentials store for the `dev-auth` stand-in (see auth/dev-auth.ts).
 *
 * The real identity schema is owned by Better Auth (tables `user`, `account`,
 * `session`, …) — see docs/schema.md. These `dev_auth_*` tables exist only so the
 * dev login persists across server restarts while Better Auth is not yet wired,
 * and are meant to be dropped when it lands. The device/pairing/trust tables below
 * follow docs/schema.md but reference `dev_auth_users` for the same reason; their
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

/** Short-lived, one-time pairing codes. `device_id` is the initiator (device A). */
export const pairingCodes = pgTable(
  'pairing_codes',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id')
      .notNull()
      .references(() => devAuthUsers.id, { onDelete: 'cascade' }),
    deviceId: uuid('device_id')
      .notNull()
      .references(() => devices.id, { onDelete: 'cascade' }),
    code: text('code').notNull(),
    expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
    usedAt: timestamp('used_at', { withTimezone: true }),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [
    check('pairing_codes_code_len', sql`length(${table.code}) between 6 and 12`),
    check('pairing_codes_expiry', sql`${table.expiresAt} > ${table.createdAt}`),
    index('pairing_codes_user_id_idx').on(table.userId),
    // An unused code is globally unique; used codes may collide/prune.
    uniqueIndex('pairing_codes_active_code_uq')
      .on(table.code)
      .where(sql`${table.usedAt} is null`),
  ],
);

/** A trusted, bidirectional relationship between two of a user's devices. */
export const deviceTrust = pgTable(
  'device_trust',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    deviceA: uuid('device_a')
      .notNull()
      .references(() => devices.id, { onDelete: 'cascade' }),
    deviceB: uuid('device_b')
      .notNull()
      .references(() => devices.id, { onDelete: 'cascade' }),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [
    check('device_trust_distinct', sql`${table.deviceA} <> ${table.deviceB}`),
    check('device_trust_ordered', sql`${table.deviceA} < ${table.deviceB}`),
    unique('device_trust_pair_uq').on(table.deviceA, table.deviceB),
  ],
);

export type DevAuthUser = typeof devAuthUsers.$inferSelect;
export type Device = typeof devices.$inferSelect;
