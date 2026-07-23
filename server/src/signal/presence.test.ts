import type { WebSocket } from 'ws';
import { describe, expect, it } from 'vitest';
import { presence } from './presence.js';

// The presence registry is a plain in-memory map, so it needs no database — a
// stub socket that records what was written to it is enough.
function stubSocket(): WebSocket & { sent: string[] } {
  const sent: string[] = [];
  return { sent, send: (data: string) => sent.push(data) } as unknown as WebSocket & {
    sent: string[];
  };
}

describe('presence registry', () => {
  it('tracks a device as online until it is removed', () => {
    const socket = stubSocket();
    expect(presence.isOnline('unit-a')).toBe(false);
    presence.add({ deviceId: 'unit-a', userId: 'u', socket, lanAddress: '1.2.3.4:1', battery: 50 });
    expect(presence.isOnline('unit-a')).toBe(true);
    expect(presence.get('unit-a')).toMatchObject({ lanAddress: '1.2.3.4:1', battery: 50 });
    presence.remove('unit-a', socket);
    expect(presence.isOnline('unit-a')).toBe(false);
    expect(presence.get('unit-a')).toBeUndefined();
  });

  it('does not let a late close clobber a reconnect', () => {
    // Network flap: the new socket authenticates before the old one's close event
    // arrives. Removing on the stale socket must be a no-op, or the device would be
    // wrongly dropped from presence while it is in fact connected.
    const stale = stubSocket();
    const fresh = stubSocket();
    presence.add({ deviceId: 'unit-b', userId: 'u', socket: stale });
    presence.add({ deviceId: 'unit-b', userId: 'u', socket: fresh });

    expect(presence.remove('unit-b', stale)).toBe(false);
    expect(presence.isOnline('unit-b')).toBe(true);
    expect(presence.get('unit-b')?.socket).toBe(fresh);

    expect(presence.remove('unit-b', fresh)).toBe(true);
    expect(presence.isOnline('unit-b')).toBe(false);
  });

  it('sendTo delivers only to a connected device', () => {
    const socket = stubSocket();
    expect(presence.sendTo('unit-c', { type: 'paired' })).toBe(false);
    presence.add({ deviceId: 'unit-c', userId: 'u', socket });
    expect(presence.sendTo('unit-c', { type: 'paired', deviceId: 'x' })).toBe(true);
    expect(socket.sent).toEqual(['{"type":"paired","deviceId":"x"}']);
    presence.remove('unit-c', socket);
  });
});
