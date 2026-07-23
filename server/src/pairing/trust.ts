import { eq, or } from 'drizzle-orm';
import { getDb } from '../db/client.js';
import { deviceTrust } from '../db/schema.js';

/** The device ids trusted (paired) with the given device, in either direction. */
export async function trustedPeerIds(deviceId: string): Promise<string[]> {
  const rows = await getDb()
    .select({ deviceA: deviceTrust.deviceA, deviceB: deviceTrust.deviceB })
    .from(deviceTrust)
    .where(or(eq(deviceTrust.deviceA, deviceId), eq(deviceTrust.deviceB, deviceId)));
  return rows.map((row) => (row.deviceA === deviceId ? row.deviceB : row.deviceA));
}
