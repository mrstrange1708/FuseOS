import { betterAuth } from 'better-auth';
import { drizzleAdapter } from 'better-auth/adapters/drizzle';
import { hashPassword, verifyPassword } from 'better-auth/crypto';
import { bearer } from 'better-auth/plugins';
import { scrypt as scryptCallback, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';
import { env } from '../config/env.js';
import { getDb } from '../db/client.js';
import { account, session, user, verification } from '../db/schema.js';

const scrypt = promisify(scryptCallback) as (
  password: string,
  salt: string,
  keylen: number,
) => Promise<Buffer>;

/** Marks a password hash carried over from the dev-auth stand-in (migration 0003). */
const LEGACY_PREFIX = 'legacy-scrypt:';

/**
 * Verifies a password against either hash format: Better Auth's own, or the dev
 * stand-in's `legacy-scrypt:<salt hex>:<scrypt hex>` (Node scrypt, 64-byte key), so
 * accounts created before Better Auth keep their passwords.
 *
 * ponytail: legacy hashes are verified, not upgraded; they go the next time the user
 * changes their password. Rehash on sign-in if the legacy format must be retired sooner.
 */
export async function verifyAnyPassword({
  hash,
  password,
}: {
  hash: string;
  password: string;
}): Promise<boolean> {
  if (!hash.startsWith(LEGACY_PREFIX)) return verifyPassword({ hash, password });
  const [salt, expectedHex] = hash.slice(LEGACY_PREFIX.length).split(':');
  if (!salt || !expectedHex) return false;
  const expected = Buffer.from(expectedHex, 'hex');
  const actual = await scrypt(password, salt, 64);
  return expected.length === actual.length && timingSafeEqual(expected, actual);
}

function createAuth() {
  return betterAuth({
    // Mounted where dev-auth was, so both clients' paths are unchanged.
    basePath: '/auth',
    secret: env.BETTER_AUTH_SECRET,
    database: drizzleAdapter(getDb(), {
      provider: 'pg',
      schema: { user, session, account, verification },
    }),
    advanced: { database: { generateId: 'uuid' } },
    emailAndPassword: {
      enabled: true,
      minPasswordLength: 8,
      maxPasswordLength: 200,
      autoSignIn: true,
      password: { hash: hashPassword, verify: verifyAnyPassword },
    },
    // A continuity app that signs you out every week is not worth having: 90 days,
    // extended at most once a day while the app is used.
    session: { expiresIn: 60 * 60 * 24 * 90, updateAge: 60 * 60 * 24 },
    // Native clients send `Authorization: Bearer <token>`; there are no cookies.
    plugins: [bearer()],
    // Observability sees only what we choose to send (CLAUDE.md principle 6).
    telemetry: { enabled: false },
  });
}

/** The two things the rest of the server needs from Better Auth. */
export interface FuseAuth {
  /** Serves Better Auth's own routes (sign-up, sign-in, sign-out). */
  handler: (request: Request) => Promise<Response>;
  /** The user a bearer token belongs to, or null for an unknown or expired one. */
  userIdForToken: (token: string) => Promise<string | null>;
}

let cached: FuseAuth | undefined;

/** Created on first use, like the database client it sits on. */
export function getAuth(): FuseAuth {
  if (!cached) {
    const auth = createAuth();
    cached = {
      handler: (request) => auth.handler(request),
      userIdForToken: async (token) => {
        const result = await auth.api.getSession({
          headers: new Headers({ authorization: `Bearer ${token}` }),
        });
        return result?.user.id ?? null;
      },
    };
  }
  return cached;
}
