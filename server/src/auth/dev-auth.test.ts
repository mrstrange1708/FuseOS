import { describe, it, expect } from 'vitest';
import { buildApp } from '../app.js';

// These exercise the real Postgres-backed dev-auth, so they need a DATABASE_URL
// (present locally via server/.env). CI has no database, so they skip there.
describe.skipIf(!process.env.DATABASE_URL)('dev auth (Postgres)', () => {
  it('signs up then signs in with the same credentials', async () => {
    const app = buildApp();
    const email = `pragya+${Date.now()}@stylicaa.com`;

    const signUp = await app.inject({
      method: 'POST',
      url: '/auth/sign-up/email',
      payload: { email, password: 'supersecret', name: 'Pragya' },
    });
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
    await app.inject({
      method: 'POST',
      url: '/auth/sign-up/email',
      payload: { email, password: 'supersecret', name: 'Pragya' },
    });
    const duplicate = await app.inject({
      method: 'POST',
      url: '/auth/sign-up/email',
      payload: { email, password: 'supersecret', name: 'Pragya' },
    });
    expect(duplicate.statusCode).toBe(409);
    await app.close();
  });
});
