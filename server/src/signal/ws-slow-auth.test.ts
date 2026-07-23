import { once } from 'node:events';
import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import { WebSocket } from 'ws';
import {
  listening,
  registerDevice,
  signUp,
  deleteUsers,
  type TestDevice,
} from '../test-support.js';

/**
 * The auth timer must not fire while a `hello` is being verified.
 *
 * This lives in its own file because it slows the auth lookup down on purpose, and the
 * only honest way to test a timeout is to be slower than it. In the main suite the
 * database answers in milliseconds, so the timer gets cleared long before it could fire
 * whether the fix is present or not — a test there passes either way and proves nothing.
 *
 * The failure this guards is real: a control plane under load takes seconds to answer,
 * and the clients hitting it hardest are the ones reconnecting after a network blip.
 * Disconnecting them at exactly that moment turns a slow server into a broken one.
 */
const AUTH_DELAY_MS = 7_000;

vi.mock('../auth/session.js', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../auth/session.js')>();
  return {
    ...actual,
    userIdForToken: async (token: string) => {
      // Stand in for a database slower than the 5s auth timeout.
      await new Promise((resolve) => setTimeout(resolve, AUTH_DELAY_MS));
      return actual.userIdForToken(token);
    },
  };
});

describe.skipIf(!process.env.DATABASE_URL)('/signal auth timer under a slow database', () => {
  let app: FastifyInstance;
  let port: number;
  let token: string;
  let userId: string;
  let device: TestDevice;

  beforeAll(async () => {
    ({ app, port } = await listening());
    const owner = await signUp(app);
    token = owner.token;
    userId = owner.userId;
    device = await registerDevice(app, token, 'Slow Mac', 'macos', 50);
  }, 60_000);

  afterAll(async () => {
    await app?.close();
    await deleteUsers(userId);
  }, 60_000);

  it('keeps a client whose hello takes longer than the timeout to verify', async () => {
    const socket = new WebSocket(`ws://127.0.0.1:${port}/signal`);
    await once(socket, 'open');

    const frames: { type: string }[] = [];
    socket.on('message', (data) => frames.push(JSON.parse(data.toString())));

    socket.send(JSON.stringify({ type: 'hello', token, deviceId: device.id }));

    // Long enough for the delayed lookup to finish, and well past the 5s timeout it
    // has to outlive.
    await new Promise((resolve) => setTimeout(resolve, AUTH_DELAY_MS + 3_000));

    expect(frames.map((frame) => frame.type)).toContain('hello-ok');
    expect(frames.map((frame) => frame.type)).not.toContain('error');
    expect(socket.readyState).toBe(WebSocket.OPEN);

    socket.close();
  }, 30_000);
});
