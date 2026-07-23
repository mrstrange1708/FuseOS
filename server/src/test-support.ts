import { eq } from 'drizzle-orm';
import type { FastifyInstance } from 'fastify';
import { buildApp } from './app.js';
import { getDb } from './db/client.js';
import { devAuthUsers } from './db/schema.js';

/**
 * TEST-ONLY helpers.
 *
 * The suites run against the shared dev Postgres, so every account they create is
 * torn down again — deleting the `dev_auth_users` row cascades to its sessions,
 * devices, pairing codes and trust rows (see db/schema.ts).
 */

/** Collision-proof suffix for emails / public keys across parallel runs. */
export function unique(): string {
  return `${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

export function auth(token: string): { authorization: string } {
  return { authorization: `Bearer ${token}` };
}

export interface TestUser {
  token: string;
  userId: string;
}

/** Creates a throwaway account and returns its bearer token + id (for cleanup). */
export async function signUp(app: FastifyInstance): Promise<TestUser> {
  const res = await app.inject({
    method: 'POST',
    url: '/auth/sign-up/email',
    payload: {
      email: `fuseos-test+${unique()}@stylicaa.com`,
      password: 'supersecret',
      name: 'Test User',
    },
  });
  if (res.statusCode !== 201) throw new Error(`sign-up failed: ${res.statusCode} ${res.body}`);
  const body = res.json<{ token: string; user: { id: string } }>();
  return { token: body.token, userId: body.user.id };
}

export interface TestDevice {
  id: string;
  publicKey: string;
}

export async function registerDevice(
  app: FastifyInstance,
  token: string,
  name: string,
  platform: 'android' | 'macos',
  battery?: number,
): Promise<TestDevice> {
  const publicKey = `pk-${unique()}`;
  const res = await app.inject({
    method: 'POST',
    url: '/devices',
    headers: auth(token),
    payload: { name, platform, publicKey, battery },
  });
  if (res.statusCode !== 201) throw new Error(`register failed: ${res.statusCode} ${res.body}`);
  return { id: res.json<{ id: string }>().id, publicKey };
}

/** Runs the real pairing flow so the two devices end up in `device_trust`. */
export async function pair(
  app: FastifyInstance,
  token: string,
  initiatorId: string,
  claimerId: string,
): Promise<void> {
  const initiate = await app.inject({
    method: 'POST',
    url: '/pairing/initiate',
    headers: auth(token),
    payload: { deviceId: initiatorId },
  });
  if (initiate.statusCode !== 201) throw new Error(`initiate failed: ${initiate.body}`);
  const claim = await app.inject({
    method: 'POST',
    url: '/pairing/claim',
    headers: auth(token),
    payload: { deviceId: claimerId, code: initiate.json<{ code: string }>().code },
  });
  if (claim.statusCode !== 200) throw new Error(`claim failed: ${claim.body}`);
}

/** Deletes the accounts a test created; everything else cascades. */
export async function deleteUsers(...userIds: string[]): Promise<void> {
  for (const id of userIds) {
    await getDb().delete(devAuthUsers).where(eq(devAuthUsers.id, id));
  }
}

/** Starts a real listening server — required for `/signal`, which is attached to
 *  the raw HTTP `upgrade` event and therefore invisible to `app.inject()`. */
export async function listening(): Promise<{ app: FastifyInstance; port: number }> {
  const app = buildApp();
  await app.listen({ port: 0, host: '127.0.0.1' });
  const address = app.server.address();
  if (address === null || typeof address === 'string') throw new Error('expected a TCP address');
  return { app, port: address.port };
}
