import { eq } from 'drizzle-orm';
import type { FastifyReply, FastifyRequest } from 'fastify';
import { getDb } from '../db/client.js';
import { devAuthSessions } from '../db/schema.js';

// The authenticated user id, attached by `authenticate` for downstream handlers.
declare module 'fastify' {
  interface FastifyRequest {
    userId?: string;
  }
}

/** Resolves a bearer token to its user id, or null if unknown. Dev stand-in for JWT verify. */
export async function userIdForToken(token: string): Promise<string | null> {
  const [row] = await getDb()
    .select({ userId: devAuthSessions.userId })
    .from(devAuthSessions)
    .where(eq(devAuthSessions.token, token))
    .limit(1);
  return row?.userId ?? null;
}

function bearerToken(request: FastifyRequest): string | null {
  const header = request.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) return null;
  const token = header.slice('Bearer '.length).trim();
  return token.length > 0 ? token : null;
}

/**
 * Fastify preHandler: requires a valid bearer token and attaches `request.userId`.
 * Replies 401 and short-circuits the route when the token is missing or unknown.
 */
export async function authenticate(request: FastifyRequest, reply: FastifyReply): Promise<void> {
  const token = bearerToken(request);
  const userId = token ? await userIdForToken(token) : null;
  if (!userId) {
    await reply.status(401).send({ error: { code: 'unauthorized', message: 'Sign in required.' } });
    return;
  }
  request.userId = userId;
}
