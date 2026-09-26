import { randomBytes, scryptSync } from 'node:crypto';
import { afterAll, describe, it, expect } from 'vitest';
import { buildApp } from '../app.js';
import { auth, deleteUsers } from '../test-support.js';
import { verifyAnyPassword } from './auth.js';
import { getDb } from '../db/client.js';
import { account, user } from '../db/schema.js';

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
