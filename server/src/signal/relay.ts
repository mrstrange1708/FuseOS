import { z } from 'zod';

/**
 * The relay: when two devices on one account can't reach each other on the LAN (a college
 * Wi-Fi that isolates clients, different networks), their channel runs over `/signal` instead.
 * What crosses is the same channel the LAN carries — the clear handshake, then AES-GCM frames
 * under keys only the two devices hold — cut into messages. The server forwards opaque bytes it
 * cannot read, never parses or logs them, and only between devices of one account
 * (docs/protocol.md §19).
 */

/** One message's bytes before base64: a sealed frame, or a piece of one. */
export const RELAY_CHUNK_BYTES = 64 * 1024;

export const relaySchema = z.object({
  type: z.literal('relay'),
  to: z.string().uuid(),
  /** One relayed channel; both ends pick the id, the dialer first. */
  stream: z.string().min(1).max(64),
  /** Base64 of up to RELAY_CHUNK_BYTES. */
  data: z
    .string()
    .max(Math.ceil(RELAY_CHUNK_BYTES / 3) * 4)
    .optional(),
  close: z.boolean().optional(),
});
export type RelayMessage = z.infer<typeof relaySchema>;

/**
 * Per-device budget, so one device cannot turn the server into a pipe for files or video:
 * the relay is for copies, notifications and commands. A bucket that refills at RATE and holds
 * BURST bytes.
 * ponytail: in this process's memory, like presence; Redis if the server ever scales out.
 */
const RATE_BYTES_PER_SEC = 256 * 1024;
const BURST_BYTES = 2 * 1024 * 1024;
const buckets = new Map<string, { tokens: number; at: number }>();

export function relayAllowed(deviceId: string, bytes: number, now = Date.now()): boolean {
  const bucket = buckets.get(deviceId) ?? { tokens: BURST_BYTES, at: now };
  bucket.tokens = Math.min(
    BURST_BYTES,
    bucket.tokens + ((now - bucket.at) / 1000) * RATE_BYTES_PER_SEC,
  );
  bucket.at = now;
  buckets.set(deviceId, bucket);
  if (bucket.tokens < bytes) return false;
  bucket.tokens -= bytes;
  return true;
}

export function forgetRelayBudget(deviceId: string): void {
  buckets.delete(deviceId);
}
