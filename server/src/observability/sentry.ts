import * as Sentry from '@sentry/node';
import type { Breadcrumb, ErrorEvent } from '@sentry/node';
import { env } from '../config/env.js';

/** A URL without its query: `/auth/verify-email?token=…` and reset links carry secrets there. */
const withoutQuery = (url: string): string => url.split('?')[0] ?? url;

/**
 * What leaves for Sentry: the error, its stack, and the route — never a body, header, cookie
 * or query string (CLAUDE.md principle 6).
 */
export function scrub(event: ErrorEvent): ErrorEvent {
  if (event.request) {
    const { method, url } = event.request;
    event.request = { method, url: url && withoutQuery(url) };
  }
  event.breadcrumbs = event.breadcrumbs?.map(scrubBreadcrumb);
  return event;
}

function scrubBreadcrumb(crumb: Breadcrumb): Breadcrumb {
  const url: unknown = crumb.data?.url;
  return typeof url === 'string'
    ? { ...crumb, data: { ...crumb.data, url: withoutQuery(url) } }
    : crumb;
}

// Initialise Sentry for error tracking: production only. A laptop's dev server filled the
// project with its own noise (a schema mid-edit, the database lost while the lid was shut —
// NODE-1..5), so dev and tests never report, whatever the env says. Errors only, as in both
// apps: no traces, and no personal data (IPs, cookies, headers).
export function initSentry(): void {
  if (!env.SENTRY_DSN || env.NODE_ENV !== 'production') return;
  Sentry.init({
    dsn: env.SENTRY_DSN,
    environment: env.NODE_ENV,
    sendDefaultPii: false,
    beforeSend: scrub,
    beforeBreadcrumb: scrubBreadcrumb,
  });
}

export { Sentry };
