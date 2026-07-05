import type { FastifyInstance } from 'fastify';
import { randomBytes, scrypt as scryptCallback, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';
import { z } from 'zod';

const scrypt = promisify(scryptCallback) as (
  password: string,
  salt: string,
  keylen: number,
) => Promise<Buffer>;

/**
 * DEV-ONLY authentication.
 *
 * This is a minimal, in-memory stand-in so the native clients have a real login
 * system to talk to today. It will be replaced by Better Auth backed by
 * PostgreSQL (the source of truth) — see docs/api.md and docs/schema.md. Do not
 * build production features on top of this store; users vanish on restart.
 */
interface StoredUser {
  id: string;
  email: string;
  name: string | null;
  salt: string;
  hash: string;
}

const usersByEmail = new Map<string, StoredUser>();

const signUpSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8).max(200),
  name: z.string().min(1).max(100).optional(),
});

const signInSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1),
});

async function hashPassword(password: string, salt: string): Promise<string> {
  const derived = await scrypt(password, salt, 64);
  return derived.toString('hex');
}

function issueSession(user: StoredUser) {
  return {
    token: randomBytes(24).toString('hex'),
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
          message: 'Enter a valid email and a password of at least 8 characters.',
        },
      });
    }
    const email = parsed.data.email.toLowerCase();
    if (usersByEmail.has(email)) {
      return reply.status(409).send({
        error: { code: 'email_taken', message: 'An account with this email already exists.' },
      });
    }
    const salt = randomBytes(16).toString('hex');
    const hash = await hashPassword(parsed.data.password, salt);
    const user: StoredUser = {
      id: randomBytes(12).toString('hex'),
      email,
      name: parsed.data.name ?? null,
      salt,
      hash,
    };
    usersByEmail.set(email, user);
    return reply.status(201).send(issueSession(user));
  });

  app.post('/auth/sign-in/email', async (request, reply) => {
    const parsed = signInSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: { code: 'invalid_request', message: 'Enter your email and password.' },
      });
    }
    const email = parsed.data.email.toLowerCase();
    const user = usersByEmail.get(email);
    if (!user) {
      return reply.status(401).send({
        error: { code: 'invalid_credentials', message: 'Incorrect email or password.' },
      });
    }
    const candidate = await hashPassword(parsed.data.password, user.salt);
    if (!safeEqualHex(candidate, user.hash)) {
      return reply.status(401).send({
        error: { code: 'invalid_credentials', message: 'Incorrect email or password.' },
      });
    }
    return reply.send(issueSession(user));
  });
}
