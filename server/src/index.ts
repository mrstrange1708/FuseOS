// Sentry must be initialised before anything else so it can instrument early.
import { initSentry, Sentry } from './observability/sentry.js';
initSentry();

import { buildApp } from './app.js';
import { env } from './config/env.js';
import { capture, shutdownAnalytics } from './observability/analytics.js';

const app = buildApp();

async function start(): Promise<void> {
  try {
    await app.listen({ port: env.PORT, host: '0.0.0.0' });
    // eslint-disable-next-line no-console
    console.log(`\n✔ FuseOS server ready → http://localhost:${env.PORT}  (leave this running)\n`);
    // Note: only non-sensitive operational metadata — never user payloads.
    capture('system', 'server_started', { port: env.PORT, env: env.NODE_ENV });
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'EADDRINUSE') {
      // eslint-disable-next-line no-console
      console.error(
        `\n⚠ Port ${env.PORT} is already in use — FuseOS is probably already running in another terminal.\n` +
          `  Stop that one (Ctrl+C in its tab), or start this one on a different port:\n` +
          `      PORT=3001 pnpm server\n`,
      );
    } else {
      Sentry.captureException(error);
      app.log.error(error);
    }
    await shutdownAnalytics();
    process.exit(1);
  }
}

void start();
