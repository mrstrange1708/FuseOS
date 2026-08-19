import Fastify, { type FastifyInstance } from 'fastify';
import { registerDevAuth } from './auth/dev-auth.js';
import { registerDeviceRoutes } from './devices/routes.js';
import { registerPairingRoutes } from './pairing/routes.js';
import { attachSignal } from './signal/ws.js';
import { Sentry } from './observability/sentry.js';

/** Builds the FuseOS control-plane app. Exported so tests can drive it via inject(). */
export function buildApp(): FastifyInstance {
  const app = Fastify({ logger: true });

  app.get('/health', async () => ({ status: 'ok' }));

  registerDevAuth(app);
  registerDeviceRoutes(app);
  registerPairingRoutes(app);
  attachSignal(app);

  app.setErrorHandler((error, _request, reply) => {
    Sentry.captureException(error);
    app.log.error(error);
    void reply.status(500).send({
      error: { code: 'internal', message: 'Internal Server Error' },
    });
  });

  return app;
}
