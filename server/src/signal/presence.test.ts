import type { WebSocket } from 'ws';
import { describe, expect, it } from 'vitest';
import { closeSilentSockets, presence, SILENCE_LIMIT_MS } from './presence.js';

// The presence registry is a plain in-memory map, so it needs no database — a
// stub socket that records what was written to it is enough.
function stubSocket(): WebSocket & { sent: string[]; terminated: boolean } {
  const socket = {
    sent: [] as string[],
    terminated: false,
    send: (data: string) => socket.sent.push(data),
    terminate: () => {
      socket.terminated = true;
    },
  };
  return socket as unknown as WebSocket & { sent: string[]; terminated: boolean };
}

describe('presence registry', () => {
  it('tracks a device as online until it is removed', () => {
    const socket = stubSocket();
    expect(presence.isOnline('unit-a')).toBe(false);
    presence.add({
      deviceId: 'unit-a',
      userId: 'u',
      socket,
      lanAddress: '1.2.3.4:1',
      battery: 50,
      lastHeard: 0,
    });
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
    presence.add({ deviceId: 'unit-b', userId: 'u', socket: stale, lastHeard: 0 });
    presence.add({ deviceId: 'unit-b', userId: 'u', socket: fresh, lastHeard: 0 });

    expect(presence.remove('unit-b', stale)).toBe(false);
    expect(presence.isOnline('unit-b')).toBe(true);
    expect(presence.get('unit-b')?.socket).toBe(fresh);

    expect(presence.remove('unit-b', fresh)).toBe(true);
    expect(presence.isOnline('unit-b')).toBe(false);
  });

  it('sendTo delivers only to a connected device', () => {
    const socket = stubSocket();
    expect(presence.sendTo('unit-c', { type: 'paired' })).toBe(false);
    presence.add({ deviceId: 'unit-c', userId: 'u', socket, lastHeard: 0 });
    expect(presence.sendTo('unit-c', { type: 'paired', deviceId: 'x' })).toBe(true);
    expect(socket.sent).toEqual(['{"type":"paired","deviceId":"x"}']);
    presence.remove('unit-c', socket);
  });

  it('the sweep closes only sockets silent past the limit', () => {
    const now = 1_000_000;
    const quiet = stubSocket();
    const talking = stubSocket();
    presence.add({
      deviceId: 'unit-d',
      userId: 'u',
      socket: quiet,
      lastHeard: now - SILENCE_LIMIT_MS - 1,
    });
    presence.add({
      deviceId: 'unit-e',
      userId: 'u',
      socket: talking,
      lastHeard: now - SILENCE_LIMIT_MS,
    });

    expect(closeSilentSockets(now)).toBe(1);
    expect(quiet.terminated).toBe(true);
    expect(talking.terminated).toBe(false);
    presence.remove('unit-d', quiet);
    presence.remove('unit-e', talking);
  });

  it('a frame from the live socket keeps it off the sweep; one from a replaced socket does not', () => {
    const now = 1_000_000;
    const old = stubSocket();
    const live = stubSocket();
    presence.add({ deviceId: 'unit-f', userId: 'u', socket: live, lastHeard: 0 });
    presence.heard('unit-f', old, now);
    expect(closeSilentSockets(now)).toBe(1);

    const again = stubSocket();
    presence.add({ deviceId: 'unit-f', userId: 'u', socket: again, lastHeard: 0 });
    presence.heard('unit-f', again, now);
    expect(closeSilentSockets(now)).toBe(0);
    presence.remove('unit-f', again);
  });
});
