import type { WebSocket } from 'ws';

/** A live `/signal` connection. Presence is in-memory only — never persisted payload. */
export interface Connection {
  deviceId: string;
  userId: string;
  socket: WebSocket;
  lanAddress?: string;
  battery?: number;
  /** When this socket last sent anything (ms). Clients heartbeat every 20 s. */
  lastHeard: number;
}

/**
 * Silence after which a socket is taken for dead. Six missed heartbeats: a dead link shows
 * within about 3 minutes (the sweep runs each minute), and a phone that dozes through one
 * or two beats is not flapped offline.
 */
export const SILENCE_LIMIT_MS = 120_000;

// One active connection per device (a reconnect replaces the previous socket).
const byDevice = new Map<string, Connection>();

export const presence = {
  add(conn: Connection): void {
    byDevice.set(conn.deviceId, conn);
  },

  /** Remove only if the stored socket is the one closing (avoids clobbering a reconnect).
   *  Returns whether the device actually went offline — false means a newer socket
   *  has already taken over and the device is still connected. */
  remove(deviceId: string, socket: WebSocket): boolean {
    const existing = byDevice.get(deviceId);
    if (!existing || existing.socket !== socket) return false;
    byDevice.delete(deviceId);
    return true;
  },

  get(deviceId: string): Connection | undefined {
    return byDevice.get(deviceId);
  },

  isOnline(deviceId: string): boolean {
    return byDevice.has(deviceId);
  },

  /** Notes that a device's live socket just spoke. A replaced socket is ignored. */
  heard(deviceId: string, socket: WebSocket, now = Date.now()): void {
    const conn = byDevice.get(deviceId);
    if (conn?.socket === socket) conn.lastHeard = now;
  },

  /** Push a JSON message to a device if it is online. Returns whether it was delivered. */
  sendTo(deviceId: string, message: unknown): boolean {
    const conn = byDevice.get(deviceId);
    if (!conn) return false;
    conn.socket.send(JSON.stringify(message));
    return true;
  },
};

/**
 * Terminates every socket silent past [SILENCE_LIMIT_MS]; each one's own close handler
 * then removes it and tells its peers. Returns how many closed. Run by the Inngest sweep.
 * ponytail: presence is in this process's memory, so one server instance; shared presence
 * (Redis) if it ever scales out.
 */
export function closeSilentSockets(now = Date.now()): number {
  let closed = 0;
  for (const conn of byDevice.values()) {
    if (now - conn.lastHeard > SILENCE_LIMIT_MS) {
      conn.socket.terminate();
      closed++;
    }
  }
  return closed;
}
