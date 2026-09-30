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

  // Signs Better Auth's session tokens. Required in production; in development Better
  // Auth falls back to a built-in dev secret and warns.
  BETTER_AUTH_SECRET: z.string().min(32).optional(),

  // This server's public URL (https://… when hosted). Better Auth derives it from each
  // request when unset, which is fine on a laptop and warned about everywhere else.
  BETTER_AUTH_URL: z.string().url().optional(),

  // The public website: the reset and email-confirmed pages live there, and it is the one
  // origin allowed to call /auth/reset-password from a browser.
  WEB_URL: z.string().url().default('https://fuseos.theshaik.dev'),

  // Sign in with Google (docs/api.md). The web client verifies Android's ID tokens (its
  // audience) and holds the secret; the Mac signs in through an iOS-type client, whose
  // tokens carry that client's id instead. Google sign-in is off unless all are set.
  GOOGLE_CLIENT_ID: z.string().min(1).optional(),
  GOOGLE_CLIENT_SECRET: z.string().min(1).optional(),
  GOOGLE_MAC_CLIENT_ID: z.string().min(1).optional(),

  // Email through Resend (email/resend.ts), sent only from Inngest jobs. Until the domain is
  // verified in Resend, only onboarding@resend.dev -> the Resend account's own address works.
  RESEND_API_KEY: z.string().min(1).optional(),
  EMAIL_FROM: z.string().min(3).default('FuseOS <onboarding@resend.dev>'),
  // The Resend segment that is the release list (Resend → Audience → Segments). Needs a
  // full-access API key; release emails and list sign-up are off without it.
  RESEND_SEGMENT_ID: z.string().min(1).optional(),

  // Error tracking (Sentry) — optional; disabled if absent.
  SENTRY_DSN: z.string().url().optional(),

  // Product analytics (PostHog) — optional; disabled if absent.
  POSTHOG_API_KEY: z.string().optional(),
  POSTHOG_HOST: z.string().url().default('https://us.i.posthog.com'),
});

export type Env = z.infer<typeof schema>;

export const env: Env = schema
  .refine((e) => e.NODE_ENV !== 'production' || e.BETTER_AUTH_SECRET !== undefined, {
    message: 'BETTER_AUTH_SECRET is required in production',
    path: ['BETTER_AUTH_SECRET'],
  })
  // Without it Better Auth takes its own address from each request's Host header — and the
  // links it emails (password reset, confirmation) would point wherever a caller claimed.
  .refine((e) => e.NODE_ENV !== 'production' || e.BETTER_AUTH_URL !== undefined, {
    message: 'BETTER_AUTH_URL is required in production',
    path: ['BETTER_AUTH_URL'],
  })
  .parse(process.env);
