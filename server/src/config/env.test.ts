import { afterEach, describe, expect, it, vi } from 'vitest';

// env.ts validates process.env at import time and throws on bad config, so each
// case re-imports it with a mutated environment.
const KEYS = ['NODE_ENV', 'PORT', 'DATABASE_URL', 'SENTRY_DSN', 'POSTHOG_HOST'] as const;
const original = Object.fromEntries(KEYS.map((key) => [key, process.env[key]]));

async function loadEnv(overrides: Partial<Record<(typeof KEYS)[number], string | undefined>>) {
  for (const [key, value] of Object.entries(overrides)) {
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
  vi.resetModules();
  return (await import('./env.js')).env;
}

afterEach(() => {
  for (const key of KEYS) {
    const value = original[key];
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
  vi.resetModules();
});

describe('env validation', () => {
  it('coerces PORT to a number', async () => {
    const env = await loadEnv({ PORT: '4321' });
    expect(env.PORT).toBe(4321);
    expect(typeof env.PORT).toBe('number');
  });

  it('leaves optional integrations undefined when unset', async () => {
    const env = await loadEnv({ SENTRY_DSN: undefined });
    expect(env.SENTRY_DSN).toBeUndefined();
    expect(env.POSTHOG_HOST).toMatch(/^https?:\/\//);
  });

  it.each([
    ['a non-numeric PORT', { PORT: 'not-a-port' }],
    ['a negative PORT', { PORT: '-1' }],
    ['a DATABASE_URL that is not a URL', { DATABASE_URL: 'postgres-but-not-a-url' }],
    ['an unknown NODE_ENV', { NODE_ENV: 'staging' }],
    ['a SENTRY_DSN that is not a URL', { SENTRY_DSN: 'nope' }],
    ['a POSTHOG_HOST that is not a URL', { POSTHOG_HOST: 'nope' }],
  ])('refuses to start with %s', async (_label, overrides) => {
    await expect(loadEnv(overrides)).rejects.toThrow();
  });
});
