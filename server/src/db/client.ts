import { drizzle, type PostgresJsDatabase } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';
import { env } from '../config/env.js';
import * as schema from './schema.js';

// The Drizzle client is created lazily on first use so that importing this module
// (e.g. from tests without a database) doesn't require DATABASE_URL. The control
// plane is the only thing that talks to Postgres — never the data plane.
let cached: PostgresJsDatabase<typeof schema> | undefined;

export function getDb(): PostgresJsDatabase<typeof schema> {
  if (!cached) {
    if (!env.DATABASE_URL) {
      throw new Error('DATABASE_URL is not set — add it to server/.env to use the database.');
    }
    const client = postgres(env.DATABASE_URL, { ssl: 'require' });
    cached = drizzle(client, { schema });
  }
  return cached;
}
