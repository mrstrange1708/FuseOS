import type { FastifyInstance } from 'fastify';
import { randomUUID } from 'node:crypto';
import { once } from 'node:events';
import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest';
import { WebSocket } from 'ws';
import {
  deleteUsers,
  listening,
  registerDevice,
  signUp,
  type TestDevice,
  type TestUser,
} from '../test-support.js';
import { presence } from './presence.js';

/**
 * `/signal` end-to-end. It is attached to the raw HTTP `upgrade` event, so
 * `app.inject()` cannot reach it — these tests drive a real listening server with
 * real `ws` clients. Presence + LAN signaling only: no payload ever crosses here.
 * Needs DATABASE_URL (server/.env); skips in CI.
 */

interface Msg {
  type: string;
  [key: string]: unknown;
}

interface PeerCard {
  deviceId: string;
  name: string;
  platform: string;
  publicKey: string;
  lanAddress: string | null;
  battery: number | null;
  online?: boolean;
}

/** Minimal test client: records every frame and lets a test await one by type. */
class SignalClient {
  readonly all: Msg[] = [];
  private readonly queue: Msg[] = [];
  private readonly waiters: { type: string; deliver: (msg: Msg) => void }[] = [];

  constructor(readonly socket: WebSocket) {
    socket.on('message', (data) => {
      const msg = JSON.parse(data.toString()) as Msg;
      this.all.push(msg);
      const index = this.waiters.findIndex((waiter) => waiter.type === msg.type);
      if (index < 0) {
        this.queue.push(msg);
        return;
      }
      const [waiter] = this.waiters.splice(index, 1);
      waiter?.deliver(msg);
    });
  }

  send(message: unknown): void {
    this.socket.send(JSON.stringify(message));
  }

  waitFor(type: string, timeoutMs = 10_000): Promise<Msg> {
    const buffered = this.queue.findIndex((msg) => msg.type === type);
    if (buffered >= 0) {
      const [msg] = this.queue.splice(buffered, 1);
      if (msg) return Promise.resolve(msg);
    }
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        const index = this.waiters.findIndex((waiter) => waiter.deliver === deliver);
        if (index >= 0) this.waiters.splice(index, 1);
        reject(
          new Error(`timed out waiting for "${type}"; saw [${this.all.map((m) => m.type).join()}]`),
        );
      }, timeoutMs);
      const deliver = (msg: Msg): void => {
        clearTimeout(timer);
        resolve(msg);
      };
      this.waiters.push({ type, deliver });
    });
  }

  types(): string[] {
    return this.all.map((msg) => msg.type);
  }

  async close(): Promise<void> {
    if (this.socket.readyState === WebSocket.CLOSED) return;
    this.socket.close();
    await once(this.socket, 'close');
  }
}

describe.skipIf(!process.env.DATABASE_URL)('/signal websocket', () => {
  let app: FastifyInstance;
  let port: number;
  let owner: TestUser;
  let mac: TestDevice;
  let phone: TestDevice;
  let stranger: TestUser;
  let strangerDevice: TestDevice;
  let open: SignalClient[] = [];

  async function connect(): Promise<SignalClient> {
    const socket = new WebSocket(`ws://127.0.0.1:${port}/signal`);
    const client = new SignalClient(socket);
    open.push(client);
    await once(socket, 'open');
    return client;
  }

  /** Connects and completes the `hello` handshake, returning the client + hello-ok. */
  async function helloAs(
    device: TestDevice,
    extra: { lanAddress?: string; battery?: number; token?: string } = {},
  ): Promise<{ client: SignalClient; helloOk: Msg }> {
    const { token = owner.token, ...rest } = extra;
    const client = await connect();
    client.send({ type: 'hello', token, deviceId: device.id, ...rest });
    return { client, helloOk: await client.waitFor('hello-ok') };
  }

  // Generous hook timeouts: vitest's default is 10s and does not follow
  // --testTimeout, which the setup's handful of Neon round trips can exceed.
  beforeAll(async () => {
    ({ app, port } = await listening());
    owner = await signUp(app);
    mac = await registerDevice(app, owner.token, 'Mac mini', 'macos', 88);
    phone = await registerDevice(app, owner.token, 'Pixel 8', 'android', 47);
    stranger = await signUp(app);
    strangerDevice = await registerDevice(app, stranger.token, 'Not yours', 'macos');
  }, 60_000);

  afterEach(async () => {
    await Promise.all(open.map((client) => client.close()));
    open = [];
    // The server's own `close` handler runs asynchronously; wait until presence has
    // actually drained so the next test starts from a known-empty state.
    for (let i = 0; i < 1_000 && (presence.isOnline(mac.id) || presence.isOnline(phone.id)); i++) {
      await new Promise((resolve) => setTimeout(resolve, 10));
    }
  }, 30_000);

  afterAll(async () => {
    await deleteUsers(...[owner?.userId, stranger?.userId].filter((id) => id !== undefined));
    await app?.close();
  }, 60_000);

  it('closes a socket that never authenticates', async () => {
    // AUTH_TIMEOUT_MS is a module constant (not configurable), so this really waits 5s.
    const client = await connect();
    const error = await client.waitFor('error', 8_000);
    expect(String(error.message)).toMatch(/timed out/i);
    await once(client.socket, 'close');
  });

  it('rejects and closes a hello with an invalid token', async () => {
    const client = await connect();
    client.send({ type: 'hello', token: 'definitely-not-a-session', deviceId: mac.id });
    const error = await client.waitFor('error');
    expect(error.message).toBe('Invalid token.');
    await once(client.socket, 'close');
  });

  it('rejects a hello claiming a device that belongs to another account', async () => {
    const client = await connect();
    client.send({ type: 'hello', token: owner.token, deviceId: strangerDevice.id });
    const error = await client.waitFor('error');
    expect(error.message).toBe('Unknown device for this account.');
    await once(client.socket, 'close');
    // ...and the device must never have been announced as online.
    expect(presence.isOnline(strangerDevice.id)).toBe(false);
  });

  it('rejects a hello for a device id that does not exist', async () => {
    const client = await connect();
    client.send({ type: 'hello', token: owner.token, deviceId: randomUUID() });
    const error = await client.waitFor('error');
    expect(error.message).toBe('Unknown device for this account.');
    await once(client.socket, 'close');
  });

  it('answers a malformed hello without closing, so the client can retry', async () => {
    const client = await connect();
    client.send({ type: 'hello', token: owner.token }); // no deviceId
    const error = await client.waitFor('error');
    expect(String(error.message)).toMatch(/hello frame/i);
    expect(client.socket.readyState).toBe(WebSocket.OPEN);
  });

  it('replies hello-ok with the trusted peers that are already online', async () => {
    const first = await helloAs(mac, { lanAddress: '192.168.1.10:47100', battery: 88 });
    expect(first.helloOk.deviceId).toBe(mac.id);
    expect(first.helloOk.peers).toEqual([]);

    const second = await helloAs(phone, { lanAddress: '192.168.1.20:47100', battery: 47 });
    const peers = second.helloOk.peers as PeerCard[];
    expect(peers).toHaveLength(1);
    expect(peers[0]).toMatchObject({
      deviceId: mac.id,
      name: 'Mac mini',
      platform: 'macos',
      publicKey: mac.publicKey,
      lanAddress: '192.168.1.10:47100',
      battery: 88,
      online: true,
    });
  });

  it('does not leak another account’s device into hello-ok peers', async () => {
    await helloAs(strangerDevice, { token: stranger.token });
    const { helloOk } = await helloAs(mac);
    expect(helloOk.peers).toEqual([]);
  });

  it('relays peer-online with the publicKey and lanAddress needed to dial the LAN', async () => {
    const a = await helloAs(mac, { lanAddress: '192.168.1.10:47100', battery: 88 });
    await helloAs(phone, { lanAddress: '192.168.1.20:47100', battery: 47 });

    const event = await a.client.waitFor('peer-online');
    expect(event).toMatchObject({
      deviceId: phone.id,
      name: 'Pixel 8',
      platform: 'android',
      publicKey: phone.publicKey,
      lanAddress: '192.168.1.20:47100',
      battery: 47,
    });
  });

  it('sends peer-update when the battery changes', async () => {
    const a = await helloAs(mac, { battery: 88 });
    const b = await helloAs(phone, { lanAddress: '192.168.1.20:47100', battery: 47 });
    await a.client.waitFor('peer-online');

    b.client.send({ type: 'heartbeat', battery: 42 });
    const update = await a.client.waitFor('peer-update');
    expect(update).toMatchObject({
      deviceId: phone.id,
      battery: 42,
      lanAddress: '192.168.1.20:47100',
    });
  });

  it('sends peer-update when only the lanAddress changes', async () => {
    // Regression guard: a peer that moved is unreachable until its peers hear the
    // new address, so an address-only change must propagate like a battery change.
    const a = await helloAs(mac, { battery: 88 });
    const b = await helloAs(phone, { lanAddress: '192.168.1.20:47100', battery: 47 });
    await a.client.waitFor('peer-online');

    b.client.send({ type: 'heartbeat', lanAddress: '10.0.0.9:47100' });
    const update = await a.client.waitFor('peer-update');
    expect(update).toMatchObject({
      deviceId: phone.id,
      lanAddress: '10.0.0.9:47100',
      battery: 47,
    });
  });

  it('stays quiet when a heartbeat repeats identical values', async () => {
    const a = await helloAs(mac, { battery: 88 });
    const b = await helloAs(phone, { lanAddress: '192.168.1.20:47100', battery: 47 });
    await a.client.waitFor('peer-online');

    // Two no-op heartbeats, then a real change. If the no-ops broadcast, the first
    // peer-update to arrive would carry battery 47 rather than 46.
    b.client.send({ type: 'heartbeat', battery: 47, lanAddress: '192.168.1.20:47100' });
    b.client.send({ type: 'heartbeat', battery: 47, lanAddress: '192.168.1.20:47100' });
    b.client.send({ type: 'heartbeat', battery: 46 });

    const update = await a.client.waitFor('peer-update');
    expect(update.battery).toBe(46);
    expect(a.client.types().filter((type) => type === 'peer-update')).toHaveLength(1);
  });

  it('tells the peer when a socket closes', async () => {
    const a = await helloAs(mac, { battery: 88 });
    const b = await helloAs(phone, { battery: 47 });
    await a.client.waitFor('peer-online');

    await b.client.close();
    const offline = await a.client.waitFor('peer-offline');
    expect(offline.deviceId).toBe(phone.id);
    expect(presence.isOnline(phone.id)).toBe(false);
  });

  it('does not announce peer-offline when a reconnect already replaced the socket', async () => {
    const a = await helloAs(mac, { battery: 88 });
    const stale = await helloAs(phone, { lanAddress: '10.0.0.1:47100', battery: 40 });
    await a.client.waitFor('peer-online');
    const fresh = await helloAs(phone, { lanAddress: '10.0.0.2:47100', battery: 41 });
    await a.client.waitFor('peer-online');

    await stale.client.close();
    // Force two full round trips through the server (the offline path is a single
    // query, so it would have landed well inside this window) before asserting
    // that nothing arrived.
    for (const battery of [42, 43]) {
      fresh.client.send({ type: 'heartbeat', battery });
      expect((await a.client.waitFor('peer-update')).battery).toBe(battery);
    }
    await new Promise((resolve) => setTimeout(resolve, 500));

    expect(a.client.types()).not.toContain('peer-offline');
    expect(presence.isOnline(phone.id)).toBe(true);
  });

  it('ignores a heartbeat from a socket a reconnect already replaced', async () => {
    // Same root cause as the peer-offline case above, on the write path. A stale
    // socket's heartbeat used to overwrite the LIVE connection's lanAddress, pointing
    // every peer at an address nobody is listening on — the precise failure that
    // propagating lanAddress at all is meant to prevent.
    const a = await helloAs(mac, { battery: 88 });
    const stale = await helloAs(phone, { lanAddress: '10.0.0.1:47100', battery: 40 });
    await a.client.waitFor('peer-online');
    const fresh = await helloAs(phone, { lanAddress: '10.0.0.2:47100', battery: 41 });
    await a.client.waitFor('peer-online');

    // The zombie insists it lives at the dead address.
    stale.client.send({ type: 'heartbeat', lanAddress: '10.0.0.1:47100', battery: 1 });

    // Drive a real round trip on the live socket so the stale frame has certainly
    // been processed by the time we assert.
    fresh.client.send({ type: 'heartbeat', battery: 42 });
    const update = await a.client.waitFor('peer-update');

    expect(update.battery).toBe(42);
    expect(update.lanAddress).toBe('10.0.0.2:47100');
    expect(presence.get(phone.id)?.lanAddress).toBe('10.0.0.2:47100');

    await stale.client.close();
  });

  it('survives non-JSON and unknown frames', async () => {
    const client = await connect();
    client.socket.send('}{ not json');
    expect(String((await client.waitFor('error')).message)).toMatch(/hello frame/i);

    client.send({ type: 'hello', token: owner.token, deviceId: mac.id });
    await client.waitFor('hello-ok');

    client.socket.send(Buffer.from([0x00, 0xff, 0x10])); // binary garbage
    client.send({ type: 'heartbeat', battery: 900 }); // out of range → ignored
    client.send({ type: 'clipboard', text: 'payloads have no business here' });

    // A protocol-level ping proves the socket is still alive...
    client.socket.ping();
    await once(client.socket, 'pong');
    expect(client.socket.readyState).toBe(WebSocket.OPEN);
    // ...and the HTTP server is still serving.
    const health = await fetch(`http://127.0.0.1:${port}/health`);
    expect(health.status).toBe(200);
  });

  it('links a brand-new device with no pairing step at all', async () => {
    // The whole "connect a device" flow: sign in on the second device, and the first
    // one hears about it the moment it says hello. No code is shown, typed or scanned.
    const existing = await helloAs(mac);
    const newcomer = await registerDevice(app, owner.token, 'Fresh laptop', 'macos');
    await helloAs(newcomer, { lanAddress: '192.168.1.30:47100' });

    const event = await existing.client.waitFor('peer-online');
    expect(event).toMatchObject({
      deviceId: newcomer.id,
      name: 'Fresh laptop',
      platform: 'macos',
      publicKey: newcomer.publicKey,
      lanAddress: '192.168.1.30:47100',
    });
  });

  it('refuses an upgrade on any path other than /signal', async () => {
    const socket = new WebSocket(`ws://127.0.0.1:${port}/not-signal`);
    await expect(once(socket, 'open')).rejects.toThrow();
  });
});
