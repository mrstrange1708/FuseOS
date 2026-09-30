import { randomBytes, scryptSync } from 'node:crypto';
import { and, eq, like } from 'drizzle-orm';
import { afterAll, describe, it, expect } from 'vitest';
import { buildApp } from '../app.js';
import { auth, deleteUsers } from '../test-support.js';
import { verifyAnyPassword } from './auth.js';
import { getDb } from '../db/client.js';
import { account, user, verification } from '../db/schema.js';

// Accounts carried over from the dev-auth stand-in keep their passwords (migration 0003).
describe('legacy password hashes', () => {
  const salt = randomBytes(16).toString('hex');
  const legacy = `legacy-scrypt:${salt}:${scryptSync('supersecret', salt, 64).toString('hex')}`;

  it('accepts the right password', async () => {
    expect(await verifyAnyPassword({ hash: legacy, password: 'supersecret' })).toBe(true);
  });

  it('refuses a wrong one', async () => {
    expect(await verifyAnyPassword({ hash: legacy, password: 'not-it' })).toBe(false);
  });

  it('refuses a malformed legacy hash', async () => {
    expect(await verifyAnyPassword({ hash: 'legacy-scrypt:nope', password: 'x' })).toBe(false);
  });
});

// These exercise the real Postgres-backed Better Auth, so they need a DATABASE_URL
// (present locally via server/.env). CI has no database, so they skip there.
describe.skipIf(!process.env.DATABASE_URL)('auth (Better Auth, Postgres)', () => {
  // The dev database is shared, so every account these tests create is removed again.
  const createdUsers: string[] = [];
  const track = <T extends { statusCode: number; json: () => { user?: { id?: string } } }>(
    res: T,
  ): T => {
    const id = res.statusCode === 201 ? res.json().user?.id : undefined;
    if (id) createdUsers.push(id);
    return res;
  };

  afterAll(async () => {
    await deleteUsers(...createdUsers);
  }, 60_000);

  it('signs up then signs in with the same credentials', async () => {
    const app = buildApp();
    const email = `pragya+${Date.now()}@stylicaa.com`;

    const signUp = track(
      await app.inject({
        method: 'POST',
        url: '/auth/sign-up/email',
        payload: { email, password: 'supersecret', name: 'Pragya' },
      }),
    );
    expect(signUp.statusCode).toBe(201);
    const signUpBody = signUp.json();
    expect(typeof signUpBody.token).toBe('string');
    expect(signUpBody.user.email).toBe(email);

    const signIn = await app.inject({
      method: 'POST',
      url: '/auth/sign-in/email',
      payload: { email, password: 'supersecret' },
    });
    expect(signIn.statusCode).toBe(200);
    expect(typeof signIn.json().token).toBe('string');

    const wrong = await app.inject({
      method: 'POST',
      url: '/auth/sign-in/email',
      payload: { email, password: 'wrong-password' },
    });
    expect(wrong.statusCode).toBe(401);

    await app.close();
  });

  it('rejects a password shorter than 8 characters', async () => {
    const app = buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/auth/sign-up/email',
      payload: { email: 'short@stylicaa.com', password: 'short', name: 'Pragya' },
    });
    expect(res.statusCode).toBe(400);
    await app.close();
  });

  it('rejects a sign-up with no name', async () => {
    const app = buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/auth/sign-up/email',
      payload: { email: `noname+${Date.now()}@stylicaa.com`, password: 'supersecret' },
    });
    expect(res.statusCode).toBe(400);
    await app.close();
  });

  it('rejects a blank name', async () => {
    const app = buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/auth/sign-up/email',
      payload: { email: `blank+${Date.now()}@stylicaa.com`, password: 'supersecret', name: '   ' },
    });
    expect(res.statusCode).toBe(400);
    await app.close();
  });

  it('rejects a duplicate email', async () => {
    const app = buildApp();
    const email = `dup+${Date.now()}@stylicaa.com`;
    track(
      await app.inject({
        method: 'POST',
        url: '/auth/sign-up/email',
        payload: { email, password: 'supersecret', name: 'Pragya' },
      }),
    );
    const duplicate = await app.inject({
      method: 'POST',
      url: '/auth/sign-up/email',
      payload: { email, password: 'supersecret', name: 'Pragya' },
    });
    expect(duplicate.statusCode).toBe(409);
    await app.close();
  });

  it('authorizes with the token and stops after sign-out', async () => {
    const app = buildApp();
    const signUp = track(
      await app.inject({
        method: 'POST',
        url: '/auth/sign-up/email',
        payload: {
          email: `session+${Date.now()}@stylicaa.com`,
          password: 'supersecret',
          name: 'Pragya',
        },
      }),
    );
    const token = signUp.json<{ token: string }>().token;

    expect(
      (await app.inject({ method: 'GET', url: '/devices', headers: auth(token) })).statusCode,
    ).toBe(200);
    const out = await app.inject({ method: 'POST', url: '/auth/sign-out', headers: auth(token) });
    expect(out.statusCode).toBe(200);
    expect(
      (await app.inject({ method: 'GET', url: '/devices', headers: auth(token) })).statusCode,
    ).toBe(401);
    await app.close();
  });

  it('answers a reset request the same way whether or not the account exists', async () => {
    const app = buildApp();
    const nobody = await app.inject({
      method: 'POST',
      url: '/auth/request-password-reset',
      payload: { email: `nobody+${Date.now()}@stylicaa.com` },
    });
    expect(nobody.statusCode).toBe(200);
    expect(nobody.json()).toEqual({ ok: true });
    const bad = await app.inject({
      method: 'POST',
      url: '/auth/request-password-reset',
      payload: {},
    });
    expect(bad.statusCode).toBe(400);
  });

  it('refuses a reset with a made-up token, in its own words', async () => {
    const res = await buildApp().inject({
      method: 'POST',
      url: '/auth/reset-password',
      payload: { token: 'made-up', newPassword: 'another-password' },
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error.code).toBe('invalid_token');
  });

  it('lets only the website call the reset endpoint from a browser', async () => {
    const app = buildApp();
    const preflight = (origin: string) =>
      app.inject({ method: 'OPTIONS', url: '/auth/reset-password', headers: { origin } });
    const ours = await preflight('https://fuseos.theshaik.dev');
    expect(ours.statusCode).toBe(204);
    expect(ours.headers['access-control-allow-origin']).toBe('https://fuseos.theshaik.dev');
    const theirs = await preflight('https://evil.example');
    expect(theirs.statusCode).toBe(403);
    expect(theirs.headers['access-control-allow-origin']).toBeUndefined();
  });

  it('sends a clicked confirmation link to the website', async () => {
    const res = await buildApp().inject({ method: 'GET', url: '/auth/verify-email?token=nope' });
    expect(res.statusCode).toBe(302);
    expect(res.headers.location).toBe('https://fuseos.theshaik.dev/verified?error=expired');
  });

  it('resets a password end to end, and signs every device out', async () => {
    const app = buildApp();
    const email = `pragya+${Date.now()}@stylicaa.com`;
    const signUp = track(
      await app.inject({
        method: 'POST',
        url: '/auth/sign-up/email',
        payload: { email, password: 'old-password', name: 'Pragya' },
      }),
    );
    const { token: session, user: created } = signUp.json();

    await app.inject({ method: 'POST', url: '/auth/request-password-reset', payload: { email } });
    // The email is an Inngest job (off under test); the token Better Auth stored is the link's.
    const [row] = await getDb()
      .select({ identifier: verification.identifier })
      .from(verification)
      .where(
        and(like(verification.identifier, 'reset-password:%'), eq(verification.value, created.id)),
      );
    const token = row?.identifier.slice('reset-password:'.length);
    expect(token).toBeTruthy();

    const reset = await app.inject({
      method: 'POST',
      url: '/auth/reset-password',
      payload: { token, newPassword: 'new-password' },
    });
    expect(reset.statusCode).toBe(200);

    const signIn = (password: string) =>
      app.inject({ method: 'POST', url: '/auth/sign-in/email', payload: { email, password } });
    expect((await signIn('old-password')).statusCode).toBe(401);
    expect((await signIn('new-password')).statusCode).toBe(200);
    // The session from before the reset no longer works.
    const devices = await app.inject({ method: 'GET', url: '/devices', headers: auth(session) });
    expect(devices.statusCode).toBe(401);
  });

  it('asks for a Google ID token', async () => {
    const res = await buildApp().inject({ method: 'POST', url: '/auth/google', payload: {} });
    expect(res.statusCode).toBe(400);
    expect(res.json().error.code).toBe('invalid_request');
  });

  it('refuses a forged Google ID token in the API error shape', async () => {
    const res = await buildApp().inject({
      method: 'POST',
      url: '/auth/google',
      payload: { idToken: 'not-a-google-token' },
    });
    // Configured (server/.env): Google's signature check fails. Not configured: says so.
    const configured = Boolean(process.env.GOOGLE_CLIENT_ID);
    expect(res.statusCode).toBe(configured ? 401 : 503);
    expect(res.json().error.code).toBe(configured ? 'invalid_google_token' : 'google_unavailable');
  });

  it('refuses an unknown token', async () => {
    const app = buildApp();
    const res = await app.inject({
      method: 'GET',
      url: '/devices',
      headers: auth('not-a-real-token'),
    });
    expect(res.statusCode).toBe(401);
    await app.close();
  });

  it('answers a wrong password in the API error shape', async () => {
    const app = buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/auth/sign-in/email',
      payload: { email: `nobody+${Date.now()}@stylicaa.com`, password: 'wrong-password' },
    });
    expect(res.statusCode).toBe(401);
    expect(res.json()).toEqual({
      error: { code: 'invalid_credentials', message: 'Incorrect email or password.' },
    });
    await app.close();
  });

  it('signs in an account migrated from dev-auth with its old password', async () => {
    const app = buildApp();
    const email = `migrated+${Date.now()}@stylicaa.com`;
    const salt = randomBytes(16).toString('hex');
    // The exact rows migration 0003 writes for a dev-auth account.
    const [row] = await getDb().insert(user).values({ name: 'Migrated', email }).returning();
    if (!row) throw new Error('insert returned no row');
    createdUsers.push(row.id);
    await getDb()
      .insert(account)
      .values({
        accountId: row.id,
        providerId: 'credential',
        userId: row.id,
        password: `legacy-scrypt:${salt}:${scryptSync('supersecret', salt, 64).toString('hex')}`,
      });

    const res = await app.inject({
      method: 'POST',
      url: '/auth/sign-in/email',
      payload: { email, password: 'supersecret' },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json().user.id).toBe(row.id);
    await app.close();
  });
});
