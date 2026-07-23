import { eq } from 'drizzle-orm';
import type { FastifyInstance } from 'fastify';
import { randomBytes, scrypt as scryptCallback, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';
import { z } from 'zod';
import { getDb } from '../db/client.js';
import { isUniqueViolation } from '../db/errors.js';
import { devAuthSessions, devAuthUsers, type DevAuthUser } from '../db/schema.js';

const scrypt = promisify(scryptCallback) as (
  password: string,
  salt: string,
  keylen: number,
) => Promise<Buffer>;

/**
 * DEV-ONLY authentication.
 *
 * A minimal stand-in so the native clients have a real login system today.
 * Users are persisted in Postgres (the `dev_auth_users` table) so accounts
 * survive server restarts. It will be replaced by Better Auth backed by the
 * canonical identity schema — see docs/api.md and docs/schema.md. Do not build
 * production features on top of this.
 */

const signUpSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8).max(200),
  name: z.string().trim().min(1).max(100),
});

const signInSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1),
});

async function hashPassword(password: string, salt: string): Promise<string> {
  const derived = await scrypt(password, salt, 64);
  return derived.toString('hex');
}

async function issueSession(user: Pick<DevAuthUser, 'id' | 'email' | 'name'>) {
  const token = randomBytes(24).toString('hex');
  await getDb().insert(devAuthSessions).values({ token, userId: user.id });
  return {
    token,
    user: { id: user.id, email: user.email, name: user.name },
  };
}

function safeEqualHex(a: string, b: string): boolean {
  const bufferA = Buffer.from(a, 'hex');
  const bufferB = Buffer.from(b, 'hex');
  if (bufferA.length !== bufferB.length) return false;
  return timingSafeEqual(bufferA, bufferB);
}

export function registerDevAuth(app: FastifyInstance): void {
  app.post('/auth/sign-up/email', async (request, reply) => {
    const parsed = signUpSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: {
          code: 'invalid_request',
          message: 'Enter your name, a valid email, and a password of at least 8 characters.',
        },
      });
    }
    const email = parsed.data.email.toLowerCase();
    const salt = randomBytes(16).toString('hex');
    const passwordHash = await hashPassword(parsed.data.password, salt);
    try {
      const [user] = await getDb()
        .insert(devAuthUsers)
        .values({ email, name: parsed.data.name, passwordSalt: salt, passwordHash })
        .returning();
      if (!user) throw new Error('sign-up insert returned no row');
      return reply.status(201).send(await issueSession(user));
    } catch (error) {
      if (isUniqueViolation(error)) {
        return reply.status(409).send({
          error: { code: 'email_taken', message: 'An account with this email already exists.' },
        });
      }
      throw error;
    }
  });

  app.post('/auth/sign-in/email', async (request, reply) => {
    const parsed = signInSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: { code: 'invalid_request', message: 'Enter your email and password.' },
      });
    }
    const email = parsed.data.email.toLowerCase();
    const [user] = await getDb()
      .select()
      .from(devAuthUsers)
      .where(eq(devAuthUsers.email, email))
      .limit(1);
    if (!user) {
      return reply.status(401).send({
        error: { code: 'invalid_credentials', message: 'Incorrect email or password.' },
      });
    }
    const candidate = await hashPassword(parsed.data.password, user.passwordSalt);
    if (!safeEqualHex(candidate, user.passwordHash)) {
      return reply.status(401).send({
        error: { code: 'invalid_credentials', message: 'Incorrect email or password.' },
      });
    }
    return reply.send(await issueSession(user));
  });
}
