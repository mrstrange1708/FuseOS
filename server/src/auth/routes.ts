import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';
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
    return forward(request, reply, { ...parsed.data, email: parsed.data.email.toLowerCase() }, 201);
  });

  app.post('/auth/sign-in/email', async (request, reply) => {
    const parsed = signInSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: { code: 'invalid_request', message: 'Enter your email and password.' },
      });
    }
    return forward(request, reply, { ...parsed.data, email: parsed.data.email.toLowerCase() });
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
    );
  });

  // The link in the verification email. Better Auth checks the token and answers with a
  // redirect (with ?error= on failure); a person clicked it, so they get a page, not JSON.
  app.get('/auth/verify-email', async (request, reply) => {
    const url = new URL(request.url, `http://${request.headers.host ?? 'localhost'}`);
    const response = await getAuth().handler(new Request(url, { method: 'GET' }));
    const failed =
      response.status >= 400 || (response.headers.get('location') ?? '').includes('error=');
    return reply
      .status(failed ? 400 : 200)
      .type('text/html; charset=utf-8')
      .send(
        page(
          failed ? 'That link has expired' : 'Email confirmed',
          failed
            ? 'Sign in to FuseOS and ask for a new confirmation email.'
            : 'Thanks — your FuseOS account is confirmed. You can close this page.',
        ),
      );
  });

  // Ends this device's session; the token stops working at once.
  app.post('/auth/sign-out', async (request, reply) => forward(request, reply, {}));
}

/** A minimal page for links opened in a browser. Only fixed strings go in — nothing echoed. */
function page(title: string, body: string): string {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title} · FuseOS</title><style>body{margin:0;min-height:100vh;display:grid;place-items:center;background:#0a0b10;color:#f3f4f6;font:16px/1.5 system-ui,sans-serif}main{max-width:26rem;padding:2rem;text-align:center}h1{color:#ff7a45;font-size:1.6rem;margin:0 0 .5rem}</style></head><body><main><h1>${title}</h1><p>${body}</p></main></body></html>`;
}
