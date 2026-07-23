import { describe, expect, it } from 'vitest';
import { buildApp } from '../app.js';

// Real Postgres-backed pairing flow; needs DATABASE_URL (server/.env). Skips in CI.
describe.skipIf(!process.env.DATABASE_URL)('devices + pairing', () => {
  async function signedUpApp() {
    const app = buildApp();
    const email = `pair+${Date.now()}-${Math.random().toString(36).slice(2)}@stylicaa.com`;
    const res = await app.inject({
      method: 'POST',
      url: '/auth/sign-up/email',
      payload: { email, password: 'supersecret', name: 'Pair Tester' },
    });
    const token = res.json().token as string;
    return { app, token };
  }

  function auth(token: string) {
    return { authorization: `Bearer ${token}` };
  }

  async function registerDevice(
    app: Awaited<ReturnType<typeof buildApp>>,
    token: string,
    name: string,
    platform: 'android' | 'macos',
    battery?: number,
  ) {
    const res = await app.inject({
      method: 'POST',
      url: '/devices',
      headers: auth(token),
      payload: {
        name,
        platform,
        publicKey: `pk-${Math.random().toString(36).slice(2)}-${Date.now()}`,
        battery,
      },
    });
    expect(res.statusCode).toBe(201);
    return res.json().id as string;
  }

  it('registers two devices, pairs them with a code, and records trust', async () => {
    const { app, token } = await signedUpApp();
    const mac = await registerDevice(app, token, 'Mac mini', 'macos', 88);
    const phone = await registerDevice(app, token, 'Pixel 8', 'android', 47);

    const initiate = await app.inject({
      method: 'POST',
      url: '/pairing/initiate',
      headers: auth(token),
      payload: { deviceId: mac },
    });
    expect(initiate.statusCode).toBe(201);
    const code = initiate.json().code as string;
    expect(code).toMatch(/^[A-Z0-9]{4}-[A-Z0-9]{4}$/);

    // A lowercased, un-grouped code still resolves (client normalizes leniently).
    const claim = await app.inject({
      method: 'POST',
      url: '/pairing/claim',
      headers: auth(token),
      payload: { deviceId: phone, code: code.replace('-', '').toLowerCase() },
    });
    expect(claim.statusCode).toBe(200);
    expect(claim.json().trustedWith.deviceId).toBe(mac);

    // The code is one-time: a second claim fails.
    const reuse = await app.inject({
      method: 'POST',
      url: '/pairing/claim',
      headers: auth(token),
      payload: { deviceId: phone, code },
    });
    expect(reuse.statusCode).toBe(404);
    expect(reuse.json().error.code).toBe('code_invalid');

    // The dashboard listing shows the phone as a trusted peer of the Mac.
    const list = await app.inject({
      method: 'GET',
      url: `/devices?self=${mac}`,
      headers: auth(token),
    });
    expect(list.statusCode).toBe(200);
    const devicesList = list.json().devices as Array<{
      id: string;
      trusted: boolean;
      battery: number | null;
    }>;
    const phoneRow = devicesList.find((d) => d.id === phone);
    expect(phoneRow?.trusted).toBe(true);
    expect(phoneRow?.battery).toBe(47);

    await app.close();
  });

  it('rejects an invalid code', async () => {
    const { app, token } = await signedUpApp();
    const phone = await registerDevice(app, token, 'Pixel', 'android');
    const res = await app.inject({
      method: 'POST',
      url: '/pairing/claim',
      headers: auth(token),
      payload: { deviceId: phone, code: 'ZZZZ-ZZZZ' },
    });
    expect(res.statusCode).toBe(404);
    expect(res.json().error.code).toBe('code_invalid');
    await app.close();
  });

  it('requires authentication', async () => {
    const app = buildApp();
    const res = await app.inject({ method: 'GET', url: '/devices' });
    expect(res.statusCode).toBe(401);
    await app.close();
  });

  it('does not let one account take over another account’s device via its public key', async () => {
    const sharedKey = `pk-shared-${Math.random().toString(36).slice(2)}-${Date.now()}`;
    const a = await signedUpApp();
    const b = await signedUpApp();

    const first = await a.app.inject({
      method: 'POST',
      url: '/devices',
      headers: auth(a.token),
      payload: { name: 'A device', platform: 'macos', publicKey: sharedKey },
    });
    expect(first.statusCode).toBe(201);

    // A different account submitting the same public key must be rejected, not
    // silently reassigned ownership.
    const takeover = await b.app.inject({
      method: 'POST',
      url: '/devices',
      headers: auth(b.token),
      payload: { name: 'B steals it', platform: 'android', publicKey: sharedKey },
    });
    expect(takeover.statusCode).toBe(409);
    expect(takeover.json().error.code).toBe('public_key_taken');

    await a.app.close();
    await b.app.close();
  });
});
