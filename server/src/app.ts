import Fastify, { type FastifyError, type FastifyInstance } from 'fastify';
import { serve } from 'inngest/fastify';
import { registerAuthRoutes } from './auth/routes.js';
import { registerDeviceRoutes } from './devices/routes.js';
import { registerFeedbackRoutes } from './feedback/routes.js';
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
  registerFeedbackRoutes(app);
  registerPairingRoutes(app);
  attachSignal(app);

  // Inngest calls in here to run the durable jobs (jobs/functions.ts); requests are signed
  // with INNGEST_SIGNING_KEY when hosted.
  app.route({
    method: ['GET', 'POST', 'PUT'],
    url: '/api/inngest',
    handler: serve({ client: inngest, functions }),
  });

  app.setErrorHandler<FastifyError>((error, _request, reply) => {
    // A malformed body or oversize payload is the client's mistake: say so, and keep it out
    // of Sentry, which is for the server's own faults.
    if (error.statusCode && error.statusCode < 500) {
      return reply.status(error.statusCode).send({
        error: { code: 'invalid_request', message: error.message },
      });
    }
    Sentry.captureException(error);
    app.log.error(error);
    void reply.status(500).send({
      error: { code: 'internal', message: 'Internal Server Error' },
    });
  });

  return app;
}
