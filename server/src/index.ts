// Sentry must be initialised before anything else so it can instrument early.
import { initSentry, Sentry } from './observability/sentry.js';
initSentry();

import Fastify from 'fastify';
import { env } from './config/env.js';
import { capture, shutdownAnalytics } from './observability/analytics.js';

const app = Fastify({ logger: true });

app.get('/health', async () => ({ status: 'ok' }));

app.setErrorHandler((error, _request, reply) => {
  Sentry.captureException(error);
  app.log.error(error);
  void reply.status(500).send({
    error: { code: 'internal', message: 'Internal Server Error' },
  });
});

async function start(): Promise<void> {
  try {
    await app.listen({ port: env.PORT, host: '0.0.0.0' });
    // Note: only non-sensitive operational metadata — never user payloads.
    capture('system', 'server_started', { port: env.PORT, env: env.NODE_ENV });
  } catch (error) {
    Sentry.captureException(error);
    app.log.error(error);
    await shutdownAnalytics();
    process.exit(1);
  }
}

void start();
