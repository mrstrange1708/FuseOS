import type { FastifyReply, FastifyRequest } from 'fastify';
import { getAuth } from './auth.js';

// The authenticated user id, attached by `authenticate` for downstream handlers.
declare module 'fastify' {
  interface FastifyRequest {
    userId?: string;
  }
}

/** Resolves a bearer token to its user id, or null if unknown or expired. */
export async function userIdForToken(token: string): Promise<string | null> {
  return getAuth().userIdForToken(token);
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
