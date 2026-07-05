import * as Sentry from '@sentry/node';
import { env } from '../config/env.js';

// Initialise Sentry for error tracking. No-op if SENTRY_DSN is not set, so local
// dev and tests run without an external dependency.
export function initSentry(): void {
  if (!env.SENTRY_DSN) return;
  Sentry.init({
    dsn: env.SENTRY_DSN,
    environment: env.NODE_ENV,
    tracesSampleRate: env.NODE_ENV === 'production' ? 0.1 : 1.0,
  });
}

export { Sentry };
