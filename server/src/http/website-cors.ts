import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { env } from '../config/env.js';

const website = new URL(env.WEB_URL).origin;

/**
 * CORS for the public website only (`WEB_URL`): the few routes its pages post to from a
 * browser (reset password, report a bug). No credentials are involved, and any other origin
 * gets no CORS headers — the browser then refuses to hand it the response.
 */
export function allowWebsite(request: FastifyRequest, reply: FastifyReply): boolean {
  if (request.headers.origin !== website) return false;
  reply
    .header('access-control-allow-origin', website)
    .header('access-control-allow-methods', 'POST')
    .header('access-control-allow-headers', 'content-type')
    .header('access-control-max-age', '600')
    .header('vary', 'origin');
  return true;
}

/** Answers the browser's preflight for `path`: yes for the website, no for anyone else. */
export function websitePreflight(app: FastifyInstance, path: string): void {
  app.options(path, async (request, reply) =>
    reply.status(allowWebsite(request, reply) ? 204 : 403).send(),
  );
}
