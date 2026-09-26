import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { buildApp } from '../app.js';
import {
  auth,
  deleteUsers,
  registerDevice,
  signUp,
  unique,
  type TestUser,
} from '../test-support.js';

// Boundary/validation coverage for the device registry. Needs DATABASE_URL
// (server/.env); skips in CI.
describe.skipIf(!process.env.DATABASE_URL)('device registry', () => {
  let app: FastifyInstance;
  let user: TestUser;

  // vitest's hook timeout defaults to 10s and does not follow --testTimeout, which
  // a couple of Neon round trips can exceed.
  beforeAll(async () => {
    app = buildApp();
    user = await signUp(app);
  }, 60_000);

  afterAll(async () => {
    if (user) await deleteUsers(user.userId);
    await app?.close();
  }, 60_000);

  function register(payload: unknown) {
    return app.inject({
      method: 'POST',
      url: '/devices',
      headers: auth(user.token),
      payload: payload as Record<string, unknown>,
    });
  }

  it.each([
    ['an unsupported platform', { name: 'Thing', platform: 'windows', publicKey: 'pk' }],
    ['a name longer than 100 characters', { name: 'x'.repeat(101), platform: 'macos' }],
    ['an empty name', { name: '', platform: 'macos' }],
    ['a whitespace-only name', { name: '   ', platform: 'macos' }],
    ['a missing publicKey', { name: 'Thing', platform: 'macos', publicKey: undefined }],
    ['an empty publicKey', { name: 'Thing', platform: 'macos', publicKey: '' }],
    ['a battery above 100', { name: 'Thing', platform: 'macos', battery: 101 }],
    ['a fractional battery', { name: 'Thing', platform: 'macos', battery: 12.5 }],
    ['no body at all', {}],
  ])('rejects %s', async (_label, body) => {
    const payload = { publicKey: `pk-${unique()}`, ...body };
    const res = await register(payload);
    expect(res.statusCode).toBe(400);
    expect(res.json().error.code).toBe('invalid_request');
  });

  it('accepts a 100-character name and battery 0 and 100', async () => {
    for (const [name, battery] of [
      ['x'.repeat(100), 0],
      ['Edge', 100],
    ] as const) {
      const res = await register({ name, platform: 'macos', publicKey: `pk-${unique()}`, battery });
      expect(res.statusCode).toBe(201);
    }
  });

  it('is idempotent by publicKey — the same key always returns the same device id', async () => {
    const publicKey = `pk-${unique()}`;
    const first = await register({ name: 'Mac mini', platform: 'macos', publicKey, battery: 80 });
    expect(first.statusCode).toBe(201);

    // A client calls this on every launch, sometimes with a renamed device.
    const second = await register({ name: 'Mac Studio', platform: 'macos', publicKey });
    expect(second.statusCode).toBe(201);
    expect(second.json().id).toBe(first.json().id);
    expect(second.json().name).toBe('Mac Studio');

    const list = await app.inject({ method: 'GET', url: '/devices', headers: auth(user.token) });
    const matches = (list.json().devices as { id: string }[]).filter(
      (device) => device.id === first.json().id,
    );
    expect(matches).toHaveLength(1);
  });

  it('flags every other device on the account as trusted via ?self=', async () => {
    const owner = await signUp(app);
    try {
      const mac = await registerDevice(app, owner.token, 'Mac mini', 'macos', 88);
      const phone = await registerDevice(app, owner.token, 'Pixel 8', 'android', 47);
      const spare = await registerDevice(app, owner.token, 'Old tablet', 'android');

      const res = await app.inject({
        method: 'GET',
        url: `/devices?self=${mac.id}`,
        headers: auth(owner.token),
      });
      expect(res.statusCode).toBe(200);
      const byId = new Map(
        (res.json().devices as { id: string; trusted: boolean; isSelf: boolean }[]).map((d) => [
          d.id,
          d,
        ]),
      );
      expect(byId.get(mac.id)).toMatchObject({ trusted: false, isSelf: true });
      expect(byId.get(phone.id)).toMatchObject({ trusted: true, isSelf: false });
      // No pairing step ran: same account is the whole trust rule.
      expect(byId.get(spare.id)).toMatchObject({ trusted: true, isSelf: false });

      // Without ?self= nothing is flagged.
      const plain = await app.inject({
        method: 'GET',
        url: '/devices',
        headers: auth(owner.token),
      });
      const flags = plain.json().devices as { trusted: boolean; isSelf: boolean }[];
      expect(flags.every((d) => !d.trusted && !d.isSelf)).toBe(true);
    } finally {
      await deleteUsers(owner.userId);
    }
  });

  it('reports offline devices with their last persisted battery', async () => {
    const device = await registerDevice(app, user.token, 'Sleeping', 'android', 33);
    const res = await app.inject({ method: 'GET', url: '/devices', headers: auth(user.token) });
    const row = (res.json().devices as { id: string; online: boolean; battery: number | null }[]) //
      .find((d) => d.id === device.id);
    expect(row).toMatchObject({ online: false, battery: 33 });
  });

  it('rejects a non-uuid ?self=', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/devices?self=not-a-uuid',
      headers: auth(user.token),
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error.code).toBe('invalid_request');
  });

  it('never lists another account’s devices', async () => {
    const other = await signUp(app);
    try {
      const theirs = await registerDevice(app, other.token, 'Theirs', 'macos');
      const res = await app.inject({ method: 'GET', url: '/devices', headers: auth(user.token) });
      const ids = (res.json().devices as { id: string }[]).map((d) => d.id);
      expect(ids).not.toContain(theirs.id);
    } finally {
      await deleteUsers(other.userId);
    }
  });

  it('removes an offline device, and it leaves the list', async () => {
    const stale = await registerDevice(app, user.token, 'Old phone', 'android');
    const res = await app.inject({
      method: 'DELETE',
      url: `/devices/${stale.id}`,
      headers: auth(user.token),
    });
    expect(res.statusCode).toBe(204);
    const list = await app.inject({ method: 'GET', url: '/devices', headers: auth(user.token) });
    expect(list.json().devices.map((d: { id: string }) => d.id)).not.toContain(stale.id);
  });

  it("never removes another account's device", async () => {
    const other = await signUp(app);
    try {
      const theirs = await registerDevice(app, other.token, 'Not yours', 'macos');
      const res = await app.inject({
        method: 'DELETE',
        url: `/devices/${theirs.id}`,
        headers: auth(user.token),
      });
      expect(res.statusCode).toBe(404);
      const list = await app.inject({ method: 'GET', url: '/devices', headers: auth(other.token) });
      expect(list.json().devices.map((d: { id: string }) => d.id)).toContain(theirs.id);
    } finally {
      await deleteUsers(other.userId);
    }
  });

  it('rejects a non-uuid device id on removal', async () => {
    const res = await app.inject({
      method: 'DELETE',
      url: '/devices/nope',
      headers: auth(user.token),
    });
    expect(res.statusCode).toBe(400);
  });

  it.each([
    ['POST', '/devices', { name: 'x', platform: 'macos', publicKey: 'k' }],
    ['GET', '/devices', undefined],
    ['DELETE', '/devices/00000000-0000-0000-0000-000000000000', undefined],
  ])('requires a bearer token: %s %s', async (method, url, payload) => {
    const anonymous = await app.inject({
      method: method as 'GET' | 'POST' | 'DELETE',
      url,
      payload,
    });
    expect(anonymous.statusCode).toBe(401);
    expect(anonymous.json().error.code).toBe('unauthorized');

    const bogus = await app.inject({
      method: method as 'GET' | 'POST' | 'DELETE',
      url,
      headers: auth('not-a-real-session-token'),
      payload,
    });
    expect(bogus.statusCode).toBe(401);

    const malformed = await app.inject({
      method: method as 'GET' | 'POST' | 'DELETE',
      url,
      headers: { authorization: user.token }, // missing the "Bearer " scheme
      payload,
    });
    expect(malformed.statusCode).toBe(401);
  });
});
