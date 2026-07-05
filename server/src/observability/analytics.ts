import { PostHog } from 'posthog-node';
import { env } from '../config/env.js';

// Product analytics via PostHog.
//
// PRIVACY INVARIANT: analytics must NEVER receive user payloads — clipboard
// contents, file bytes, image data, etc. Those live only on the LAN data plane
// and must not leak into any third-party service. The guard below enforces this
// at the boundary so a careless `capture()` call fails loudly instead of
// silently exfiltrating user data. See CLAUDE.md and docs/observability.md.
const FORBIDDEN_KEYS = [
  'text',
  'content',
  'clipboard',
  'clip',
  'payload',
  'data',
  'filedata',
  'file',
  'image',
  'body',
] as const;

export type AnalyticsProps = Record<string, string | number | boolean | null | undefined>;

export function assertNoPayload(properties: AnalyticsProps): void {
  for (const key of Object.keys(properties)) {
    if ((FORBIDDEN_KEYS as readonly string[]).includes(key.toLowerCase())) {
      throw new Error(
        `analytics: forbidden property "${key}" — user payloads must never be sent to PostHog`,
      );
    }
  }
}

let client: PostHog | null = null;
if (env.POSTHOG_API_KEY) {
  client = new PostHog(env.POSTHOG_API_KEY, { host: env.POSTHOG_HOST });
}

export function capture(distinctId: string, event: string, properties: AnalyticsProps = {}): void {
  assertNoPayload(properties);
  client?.capture({ distinctId, event, properties });
}

export async function shutdownAnalytics(): Promise<void> {
  await client?.shutdown();
}
