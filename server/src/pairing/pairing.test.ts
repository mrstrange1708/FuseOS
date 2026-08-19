import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildApp } from '../app.js';
import { auth, deleteUsers, registerDevice, signUp, type TestUser } from '../test-support.js';

/**
 * Manual linking is the safety net, not the trust rule — claiming a code hands over a peer
 * card, it does not grant access. These cover the two things that matter: a code introduces
 * two of *your* devices, and it can never introduce someone else's.
 */
describe('manual linking', () => {
  let app: FastifyInstance;
  let owner: TestUser;

  beforeAll(async () => {
    app = buildApp();
    await app.ready();
    owner = await signUp(app);
  }, 60_000);

  afterAll(async () => {
    await deleteUsers(owner.userId);
    await app.close();
  }, 60_000);

  async function initiate(token: string, deviceId: string) {
    return app.inject({
      method: 'POST',
      url: '/pairing/initiate',
      headers: auth(token),
      payload: { deviceId },
    });
  }

  async function claim(token: string, deviceId: string, code: string) {
    return app.inject({
      method: 'POST',
      url: '/pairing/claim',
      headers: auth(token),
      payload: { deviceId, code },
    });
  }

  it('returns the other device’s peer card so it can be dialled directly', async () => {
    const mac = await registerDevice(app, owner.token, 'Mac mini', 'macos');
    const phone = await registerDevice(app, owner.token, 'Pixel 8', 'android');

    const issued = await initiate(owner.token, mac.id);
    expect(issued.statusCode).toBe(201);
    const code = issued.json<{ code: string }>().code;
    expect(code).toMatch(/^[A-Z2-9]{4}-[A-Z2-9]{4}$/);

    const claimed = await claim(owner.token, phone.id, code);
    expect(claimed.statusCode).toBe(200);
    // The public key is the whole point: it is what authenticates the LAN handshake.
    expect(claimed.json().trustedWith).toMatchObject({
      deviceId: mac.id,
      name: 'Mac mini',
      platform: 'macos',
      publicKey: mac.publicKey,
    });
  });

  it('accepts a lowercase, dash-formatted code', async () => {
    const mac = await registerDevice(app, owner.token, 'Mac 2', 'macos');
    const phone = await registerDevice(app, owner.token, 'Phone 2', 'android');
    const code = (await initiate(owner.token, mac.id)).json<{ code: string }>().code;

    const claimed = await claim(owner.token, phone.id, code.toLowerCase());
    expect(claimed.statusCode).toBe(200);
  });

  it('spends the code, so a shoulder-surfed one cannot be replayed', async () => {
    const mac = await registerDevice(app, owner.token, 'Mac 3', 'macos');
    const phone = await registerDevice(app, owner.token, 'Phone 3', 'android');
    const code = (await initiate(owner.token, mac.id)).json<{ code: string }>().code;

    expect((await claim(owner.token, phone.id, code)).statusCode).toBe(200);
    const replay = await claim(owner.token, phone.id, code);
    expect(replay.statusCode).toBe(404);
    expect(replay.json().error.code).toBe('code_invalid');
  });

  it('refuses a code claimed by the device that issued it', async () => {
    const mac = await registerDevice(app, owner.token, 'Mac 4', 'macos');
    const code = (await initiate(owner.token, mac.id)).json<{ code: string }>().code;

    const res = await claim(owner.token, mac.id, code);
    expect(res.statusCode).toBe(400);
    expect(res.json().error.code).toBe('same_device');
  });

  it('never introduces a device on another account', async () => {
    const stranger = await signUp(app);
    try {
      const mine = await registerDevice(app, owner.token, 'Mac 5', 'macos');
      const theirs = await registerDevice(app, stranger.token, 'Their phone', 'android');
      const code = (await initiate(owner.token, mine.id)).json<{ code: string }>().code;

      // Their device, their token, my code: reads as invalid, not as forbidden — whether
      // a code exists on another account is not the caller's business.
      const res = await claim(stranger.token, theirs.id, code);
      expect(res.statusCode).toBe(404);
      expect(res.json().error.code).toBe('code_invalid');
    } finally {
      await deleteUsers(stranger.userId);
    }
  });

  it('rejects a device that is not the caller’s', async () => {
    const stranger = await signUp(app);
    try {
      const theirs = await registerDevice(app, stranger.token, 'Not mine', 'macos');
      const res = await initiate(owner.token, theirs.id);
      expect(res.statusCode).toBe(404);
      expect(res.json().error.code).toBe('device_not_found');
    } finally {
      await deleteUsers(stranger.userId);
    }
  });
});
