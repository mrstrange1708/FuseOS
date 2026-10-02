import { describe, expect, it } from 'vitest';
import { relayAllowed, relaySchema, RELAY_CHUNK_BYTES } from './relay.js';

describe('relay limits', () => {
  it('lets a burst through, then holds a device to its rate', () => {
    const t = 1_000_000;
    expect(relayAllowed('d1', 2 * 1024 * 1024, t)).toBe(true); // the whole burst
    expect(relayAllowed('d1', 1024, t)).toBe(false); // empty
    expect(relayAllowed('d1', 256 * 1024, t + 1_000)).toBe(true); // a second refills 256 KB
    expect(relayAllowed('d2', 1024, t)).toBe(true); // budgets are per device
  });

  it('refuses a chunk bigger than one sealed piece', () => {
    const tooBig = 'A'.repeat(Math.ceil(RELAY_CHUNK_BYTES / 3) * 4 + 4);
    const ok = { type: 'relay', to: crypto.randomUUID(), stream: 's' };
    expect(relaySchema.safeParse({ ...ok, data: 'AAAA' }).success).toBe(true);
    expect(relaySchema.safeParse({ ...ok, data: tooBig }).success).toBe(false);
  });
});
