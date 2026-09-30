import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { env } from '../config/env.js';
import { capture } from '../observability/analytics.js';
import { getAuth } from './auth.js';

/**
 * The auth routes the clients use, served by Better Auth behind a thin adapter.
 *
 * Bodies are Zod-validated here before Better Auth sees them (CLAUDE.md principle 3b),
 * and Better Auth's `{ code, message }` errors are reshaped into this API's
 * `{ error: { code, message } }` so neither client had to change when it arrived.
 */

const signUpSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8).max(200),
  name: z.string().trim().min(1).max(100),
});

const signInSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1),
});

const resetRequestSchema = z.object({ email: z.string().email() });
const resetSchema = z.object({
  token: z.string().min(1).max(500),
  newPassword: z.string().min(8).max(200),
});

// A Google ID token (a JWT) from the device's own Google sign-in.
const googleSchema = z.object({ idToken: z.string().min(1).max(8192) });

/** Better Auth's error codes, in this API's words. Anything else passes through. */
const knownErrors: Record<string, { status: number; code: string; message: string }> = {
  USER_ALREADY_EXISTS: {
    status: 409,
    code: 'email_taken',
    message: 'An account with this email already exists.',
  },
  USER_ALREADY_EXISTS_USE_ANOTHER_EMAIL: {
    status: 409,
    code: 'email_taken',
    message: 'An account with this email already exists.',
  },
  INVALID_EMAIL_OR_PASSWORD: {
    status: 401,
    code: 'invalid_credentials',
    message: 'Incorrect email or password.',
  },
  INVALID_TOKEN: {
    status: 401,
    code: 'invalid_google_token',
    message: "Google didn't confirm that sign-in. Try again.",
  },
  PROVIDER_NOT_FOUND: {
    status: 503,
    code: 'google_unavailable',
    message: "Google sign-in isn't set up on this server yet.",
  },
  // An account with this email exists and its email was never verified, so it is not
  // linked to Google (see auth.ts).
  OAUTH_LINK_ERROR: {
    status: 409,
    code: 'use_password',
    message: 'This email already has a FuseOS account. Sign in with your password.',
  },
};

async function forward(
  request: FastifyRequest,
  reply: FastifyReply,
  body: unknown,
  successStatus?: number,
  path?: string,
  /** On success, an analytics event for the account: its id and how, nothing else. */
  track?: { event: string; method: 'email' | 'google' },
): Promise<FastifyReply> {
  const url = new URL(path ?? request.url, `http://${request.headers.host ?? 'localhost'}`);
  const headers = new Headers({ 'content-type': 'application/json' });
  if (request.headers.authorization) headers.set('authorization', request.headers.authorization);
  const response = await getAuth().handler(
    new Request(url, {
      method: request.method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    }),
  );
  const text = await response.text();
  const json: unknown = text ? JSON.parse(text) : null;

  if (!response.ok) {
    const raw = z
      .object({ code: z.string().optional(), message: z.string().optional() })
      .safeParse(json);
    const betterAuthCode = raw.success ? raw.data.code : undefined;
    const known = betterAuthCode ? knownErrors[betterAuthCode] : undefined;
    return reply.status(known?.status ?? response.status).send({
      error: {
        code: known?.code ?? betterAuthCode?.toLowerCase() ?? 'auth_error',
        message:
          known?.message ?? (raw.success ? raw.data.message : undefined) ?? 'Sign-in failed.',
      },
    });
  }
  if (track) {
    const account = z.object({ user: z.object({ id: z.string() }) }).safeParse(json);
    if (account.success) capture(account.data.user.id, track.event, { method: track.method });
  }
  return reply.status(successStatus ?? response.status).send(json);
}

export function registerAuthRoutes(app: FastifyInstance): void {
  app.post('/auth/sign-up/email', async (request, reply) => {
    const parsed = signUpSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: {
          code: 'invalid_request',
          message: 'Enter your name, a valid email, and a password of at least 8 characters.',
        },
      });
    }
    // 201, as this route always answered: an account was created.
    return forward(
      request,
      reply,
      { ...parsed.data, email: parsed.data.email.toLowerCase() },
      201,
      undefined,
      { event: 'signed_up', method: 'email' },
    );
  });

  app.post('/auth/sign-in/email', async (request, reply) => {
    const parsed = signInSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: { code: 'invalid_request', message: 'Enter your email and password.' },
      });
    }
    return forward(
      request,
      reply,
      { ...parsed.data, email: parsed.data.email.toLowerCase() },
      undefined,
      undefined,
      { event: 'signed_in', method: 'email' },
    );
  });

  // Sign in (or sign up) with Google: the app hands over the ID token it got on the
  // device, and gets the same `{ token, user }` as an email sign-in.
  app.post('/auth/google', async (request, reply) => {
    const parsed = googleSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: { code: 'invalid_request', message: 'Google sign-in failed. Try again.' },
      });
    }
    return forward(
      request,
      reply,
      { provider: 'google', idToken: { token: parsed.data.idToken } },
      undefined,
      '/auth/sign-in/social',
      { event: 'signed_in', method: 'google' },
    );
  });

  // The link in the verification email. Better Auth checks the token and answers with a
  // redirect (with ?error= on failure); a person clicked it, so they get a page, not JSON.
  app.get('/auth/verify-email', async (request, reply) => {
    const url = new URL(request.url, `http://${request.headers.host ?? 'localhost'}`);
    const response = await getAuth().handler(new Request(url, { method: 'GET' }));
    const failed =
      response.status >= 400 || (response.headers.get('location') ?? '').includes('error=');
    // A person clicked this in their inbox: land them on the website, not on JSON.
    return reply.redirect(
      new URL(failed ? '/verified?error=expired' : '/verified', env.WEB_URL).href,
    );
  });

  // "Forgot password?" in the apps. Always the same answer, account or not, so the form
  // cannot be used to find out who has an account. Rate-limited by Better Auth.
  app.post('/auth/request-password-reset', async (request, reply) => {
    const parsed = resetRequestSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: { code: 'invalid_request', message: 'Enter the email you signed up with.' },
      });
    }
    const url = new URL(
      '/auth/request-password-reset',
      `http://${request.headers.host ?? 'localhost'}`,
    );
    const response = await getAuth().handler(
      new Request(url, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ email: parsed.data.email.toLowerCase() }),
      }),
    );
    // No account id: the answer must not depend on whether the account exists.
    capture('anonymous', 'password_reset_requested');
    if (response.status === 429) {
      return reply.status(429).send({
        error: { code: 'rate_limited', message: 'Too many tries. Wait a minute and try again.' },
      });
    }
    return reply.send({ ok: true });
  });

  // The website's /reset page posts here from another origin (fuseos.theshaik.dev → the API),
  // so this one route answers CORS — for the website only, no credentials involved.
  const website = new URL(env.WEB_URL).origin;
  const allowWebsite = (request: FastifyRequest, reply: FastifyReply): boolean => {
    if (request.headers.origin !== website) return false;
    reply
      .header('access-control-allow-origin', website)
      .header('access-control-allow-methods', 'POST')
      .header('access-control-allow-headers', 'content-type')
      .header('access-control-max-age', '600')
      .header('vary', 'origin');
    return true;
  };
  app.options('/auth/reset-password', async (request, reply) =>
    reply.status(allowWebsite(request, reply) ? 204 : 403).send(),
  );

  app.post('/auth/reset-password', async (request, reply) => {
    allowWebsite(request, reply);
    const parsed = resetSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: { code: 'invalid_request', message: 'Use a password of 8 to 200 characters.' },
      });
    }
    const url = new URL('/auth/reset-password', `http://${request.headers.host ?? 'localhost'}`);
    const response = await getAuth().handler(
      new Request(url, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(parsed.data),
      }),
    );
    if (!response.ok) {
      return reply.status(400).send({
        error: {
          code: 'invalid_token',
          message: 'This link has expired or was already used. Ask for a new one in the app.',
        },
      });
    }
    return reply.send({ ok: true });
  });

  // Ends this device's session; the token stops working at once.
  app.post('/auth/sign-out', async (request, reply) => forward(request, reply, {}));
}
