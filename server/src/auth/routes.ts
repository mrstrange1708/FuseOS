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
};

async function forward(
  request: FastifyRequest,
  reply: FastifyReply,
  body: unknown,
  successStatus?: number,
): Promise<FastifyReply> {
  const url = new URL(request.url, `http://${request.headers.host ?? 'localhost'}`);
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

  // Ends this device's session; the token stops working at once.
  app.post('/auth/sign-out', async (request, reply) => forward(request, reply, {}));
}
