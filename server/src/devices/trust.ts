import { and, eq, ne } from 'drizzle-orm';
import { getDb } from '../db/client.js';
import { devices } from '../db/schema.js';

/**
 * The device ids this device is trusted with: every *other* device on the same account.
 *
 * Trust is account membership. Both devices proved who they are at sign-in, and FuseOS
 * only ever links a user's own devices (see the v1 scope in CLAUDE.md), so a pairing code
 * asked the user to prove a second time what the login already established — and did it
 * with an 8-character code typed between two screens. Signing in on the phone is now the
 * whole link step; the peer cards flow the moment it connects to `/signal`.
 */
export async function trustedPeerIds(deviceId: string): Promise<string[]> {
  const db = getDb();
  const [self] = await db
    .select({ userId: devices.userId })
    .from(devices)
    .where(eq(devices.id, deviceId))
    .limit(1);
  if (!self) return [];
  const rows = await db
    .select({ id: devices.id })
    .from(devices)
    .where(and(eq(devices.userId, self.userId), ne(devices.id, deviceId)));
  return rows.map((row) => row.id);
}
