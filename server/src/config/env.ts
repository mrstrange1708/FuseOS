import { z } from 'zod';

// Load server/.env into process.env for local dev, if present. In CI and
// production the environment is provided directly, so a missing file is fine.
try {
  process.loadEnvFile();
} catch {
  // No .env file — fall back to the ambient environment.
}

// All configuration comes from the environment and is validated here, at the
// boundary, before anything else in the server runs (see CLAUDE.md: "never let
// bad data in"). Observability integrations are optional in local dev.
const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().positive().default(3000),

  // Control-plane data store (source of truth for identity). Optional until wired.
  DATABASE_URL: z.string().url().optional(),

  // Error tracking (Sentry) — optional; disabled if absent.
  SENTRY_DSN: z.string().url().optional(),

  // Product analytics (PostHog) — optional; disabled if absent.
  POSTHOG_API_KEY: z.string().optional(),
  POSTHOG_HOST: z.string().url().default('https://us.i.posthog.com'),
});

export type Env = z.infer<typeof schema>;

export const env: Env = schema.parse(process.env);
