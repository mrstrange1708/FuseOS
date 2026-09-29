import Fastify, { type FastifyInstance } from 'fastify';
import { serve } from 'inngest/fastify';
import { registerAuthRoutes } from './auth/routes.js';
import { registerDeviceRoutes } from './devices/routes.js';
import { registerPairingRoutes } from './pairing/routes.js';
import { attachSignal } from './signal/ws.js';
import { functions } from './jobs/functions.js';
import { inngest } from './jobs/inngest.js';
import { Sentry } from './observability/sentry.js';

/** Builds the FuseOS control-plane app. Exported so tests can drive it via inject(). */
export function buildApp(): FastifyInstance {
  const app = Fastify({ logger: true });

  app.get('/health', async () => ({ status: 'ok' }));

  registerAuthRoutes(app);
  registerDeviceRoutes(app);
  registerPairingRoutes(app);
  attachSignal(app);

  // Inngest calls in here to run the durable jobs (jobs/functions.ts); requests are signed
  // with INNGEST_SIGNING_KEY when hosted.
  app.route({
    method: ['GET', 'POST', 'PUT'],
    url: '/api/inngest',
    handler: serve({ client: inngest, functions }),
  });

  app.setErrorHandler((error, _request, reply) => {
    Sentry.captureException(error);
    app.log.error(error);
    void reply.status(500).send({
      error: { code: 'internal', message: 'Internal Server Error' },
    });
  });

  return app;
}
