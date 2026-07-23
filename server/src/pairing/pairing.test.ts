import type { FastifyInstance } from 'fastify';
import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { buildApp } from '../app.js';
import { getDb } from '../db/client.js';
import { pairingCodes } from '../db/schema.js';
import {
  auth,
  deleteUsers,
  registerDevice,
  signUp,
  unique,
  type TestUser,
} from '../test-support.js';

// Real Postgres-backed pairing flow; needs DATABASE_URL (server/.env). Skips in CI.
describe.skipIf(!process.env.DATABASE_URL)('devices + pairing', () => {
  let app: FastifyInstance;
  const createdUsers: string[] = [];

  async function newUser(): Promise<TestUser> {
    const user = await signUp(app);
    createdUsers.push(user.userId);
    return user;
  }

  beforeAll(() => {
    app = buildApp();
  });

  // Shared dev database: every account this suite creates is removed again, which
  // cascades to its devices, pairing codes and trust rows.
  afterAll(async () => {
    await deleteUsers(...createdUsers);
    await app.close();
  }, 60_000);

  it('registers two devices, pairs them with a code, and records trust', async () => {
    const { token } = await newUser();
    const mac = await registerDevice(app, token, 'Mac mini', 'macos', 88);
    const phone = await registerDevice(app, token, 'Pixel 8', 'android', 47);

    const initiate = await app.inject({
      method: 'POST',
      url: '/pairing/initiate',
      headers: auth(token),
      payload: { deviceId: mac.id },
    });
    expect(initiate.statusCode).toBe(201);
    const code = initiate.json().code as string;
    expect(code).toMatch(/^[A-Z0-9]{4}-[A-Z0-9]{4}$/);

    // A lowercased, un-grouped code still resolves (client normalizes leniently).
    const claim = await app.inject({
      method: 'POST',
      url: '/pairing/claim',
      headers: auth(token),
      payload: { deviceId: phone.id, code: code.replace('-', '').toLowerCase() },
    });
    expect(claim.statusCode).toBe(200);
    expect(claim.json().trustedWith).toMatchObject({
      deviceId: mac.id,
      name: 'Mac mini',
      platform: 'macos',
      publicKey: mac.publicKey,
    });

    // The code is one-time: a second claim fails.
    const reuse = await app.inject({
      method: 'POST',
      url: '/pairing/claim',
      headers: auth(token),
      payload: { deviceId: phone.id, code },
    });
    expect(reuse.statusCode).toBe(404);
    expect(reuse.json().error.code).toBe('code_invalid');

    // The dashboard listing shows the phone as a trusted peer of the Mac.
    const list = await app.inject({
      method: 'GET',
      url: `/devices?self=${mac.id}`,
      headers: auth(token),
    });
    expect(list.statusCode).toBe(200);
    const devicesList = list.json().devices as Array<{
      id: string;
      trusted: boolean;
      battery: number | null;
    }>;
    const phoneRow = devicesList.find((d) => d.id === phone.id);
    expect(phoneRow?.trusted).toBe(true);
    expect(phoneRow?.battery).toBe(47);
  });

  it('issues an 8-character code from an unambiguous alphabet, valid for 5 minutes', async () => {
    const { token } = await newUser();
    const mac = await registerDevice(app, token, 'Mac mini', 'macos');

    // Generate a handful so a stray I/O/0/1 is actually likely to be caught.
    for (let attempt = 0; attempt < 5; attempt++) {
      const before = Date.now();
      const res = await app.inject({
        method: 'POST',
        url: '/pairing/initiate',
        headers: auth(token),
        payload: { deviceId: mac.id },
      });
      const after = Date.now();
      expect(res.statusCode).toBe(201);
      const body = res.json() as { code: string; expiresAt: string };

      // Grouped XXXX-XXXX, and the alphabet omits the ambiguous I, O, 0 and 1.
      expect(body.code).toMatch(/^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$/);
      expect(body.code.replace('-', '')).toHaveLength(8);

      // The server stamps expiry somewhere between `before` and `after`, so a
      // 5-minute TTL is pinned exactly by bracketing it — no latency slack needed.
      const expiresAt = new Date(body.expiresAt).getTime();
      expect(expiresAt - before).toBeGreaterThanOrEqual(5 * 60_000);
      expect(expiresAt - after).toBeLessThanOrEqual(5 * 60_000);
    }
  });

  it('rejects an invalid code', async () => {
    const { token } = await newUser();
    const phone = await registerDevice(app, token, 'Pixel', 'android');
    const res = await app.inject({
      method: 'POST',
      url: '/pairing/claim',
      headers: auth(token),
      payload: { deviceId: phone.id, code: 'ZZZZ-ZZZZ' },
    });
    expect(res.statusCode).toBe(404);
    expect(res.json().error.code).toBe('code_invalid');
  });

  it('rejects an expired code', async () => {
    const { token, userId } = await newUser();
    const mac = await registerDevice(app, token, 'Mac mini', 'macos');
    const phone = await registerDevice(app, token, 'Pixel', 'android');

    // Waiting out the real 5-minute TTL is not an option, so seed a code that
    // already lapsed (created_at must stay before expires_at — schema CHECK).
    const code = `EXP${randomUUID().replace(/-/g, '').slice(0, 5)}`.toUpperCase();
    await getDb()
      .insert(pairingCodes)
      .values({
        userId,
        deviceId: mac.id,
        code,
        createdAt: new Date(Date.now() - 20 * 60_000),
        expiresAt: new Date(Date.now() - 15 * 60_000),
      });

    const res = await app.inject({
      method: 'POST',
      url: '/pairing/claim',
      headers: auth(token),
      payload: { deviceId: phone.id, code },
    });
    expect(res.statusCode).toBe(410);
    expect(res.json().error.code).toBe('code_expired');
  });

  it('rejects claiming a device’s own code', async () => {
    const { token } = await newUser();
    const mac = await registerDevice(app, token, 'Mac mini', 'macos');

    const initiate = await app.inject({
      method: 'POST',
      url: '/pairing/initiate',
      headers: auth(token),
      payload: { deviceId: mac.id },
    });
    const res = await app.inject({
      method: 'POST',
      url: '/pairing/claim',
      headers: auth(token),
      payload: { deviceId: mac.id, code: initiate.json().code },
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error.code).toBe('same_device');
  });

  it('will not initiate pairing for a device the caller does not own', async () => {
    const owner = await newUser();
    const intruder = await newUser();
    const mac = await registerDevice(app, owner.token, 'Mac mini', 'macos');

    const res = await app.inject({
      method: 'POST',
      url: '/pairing/initiate',
      headers: auth(intruder.token),
      payload: { deviceId: mac.id },
    });
    expect(res.statusCode).toBe(404);
    expect(res.json().error.code).toBe('device_not_found');

    const missing = await app.inject({
      method: 'POST',
      url: '/pairing/initiate',
      headers: auth(owner.token),
      payload: { deviceId: randomUUID() },
    });
    expect(missing.statusCode).toBe(404);
  });

  it('will not let another account claim a code it happened to see', async () => {
    const owner = await newUser();
    const intruder = await newUser();
    const mac = await registerDevice(app, owner.token, 'Mac mini', 'macos');
    const theirPhone = await registerDevice(app, intruder.token, 'Their phone', 'android');

    const initiate = await app.inject({
      method: 'POST',
      url: '/pairing/initiate',
      headers: auth(owner.token),
      payload: { deviceId: mac.id },
    });
    const res = await app.inject({
      method: 'POST',
      url: '/pairing/claim',
      headers: auth(intruder.token),
      payload: { deviceId: theirPhone.id, code: initiate.json().code },
    });
    // Codes are scoped to the user, so another account's code simply does not exist.
    expect(res.statusCode).toBe(404);
    expect(res.json().error.code).toBe('code_invalid');
  });

  it.each([
    ['a non-uuid deviceId', { deviceId: 'nope', code: 'ABCD-EFGH' }],
    ['a missing code', { deviceId: randomUUID() }],
    ['a too-short code', { deviceId: randomUUID(), code: 'AB' }],
    ['an over-long code', { deviceId: randomUUID(), code: 'A'.repeat(21) }],
  ])('rejects a claim with %s', async (_label, payload) => {
    const { token } = await newUser();
    const res = await app.inject({
      method: 'POST',
      url: '/pairing/claim',
      headers: auth(token),
      payload,
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error.code).toBe('invalid_request');
  });

  it('requires authentication', async () => {
    const res = await app.inject({ method: 'GET', url: '/devices' });
    expect(res.statusCode).toBe(401);
  });

  it('does not let one account take over another account’s device via its public key', async () => {
    const sharedKey = `pk-shared-${unique()}`;
    const a = await newUser();
    const b = await newUser();

    const first = await app.inject({
      method: 'POST',
      url: '/devices',
      headers: auth(a.token),
      payload: { name: 'A device', platform: 'macos', publicKey: sharedKey },
    });
    expect(first.statusCode).toBe(201);

    // A different account submitting the same public key must be rejected, not
    // silently reassigned ownership.
    const takeover = await app.inject({
      method: 'POST',
      url: '/devices',
      headers: auth(b.token),
      payload: { name: 'B steals it', platform: 'android', publicKey: sharedKey },
    });
    expect(takeover.statusCode).toBe(409);
    expect(takeover.json().error.code).toBe('public_key_taken');
  });
});
