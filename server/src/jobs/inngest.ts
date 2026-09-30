import { Inngest } from 'inngest';
import { env } from '../config/env.js';
import { Sentry } from '../observability/sentry.js';

/**
 * The one Inngest client (CLAUDE.md principle 5: durable work is an Inngest function).
 * Locally: `INNGEST_DEV=1` and `npx inngest-cli@latest dev` (the `inngest` mprocs pane).
 * Hosted: `INNGEST_EVENT_KEY` and `INNGEST_SIGNING_KEY` from Inngest Cloud.
 */
export const inngest = new Inngest({ id: 'fuseos' });

/**
 * Queues an event without holding up the request that caused it: a sign-up or a device
 * registration must not fail because Inngest is briefly unreachable. Once queued the job is
 * durable (retries); a failure to queue is reported, never swallowed.
 */
export function emit(event: { name: string; data: Record<string, unknown> }): void {
  // The suite signs up real-looking addresses; a test run must never email anyone.
  if (env.NODE_ENV === 'test') return;
  inngest.send(event).catch((error: unknown) => {
    Sentry.captureException(error);
    console.error(`inngest: could not queue ${event.name}:`, error);
  });
}
