import type { WebSocket } from 'ws';

/** A live `/signal` connection. Presence is in-memory only — never persisted payload. */
export interface Connection {
  deviceId: string;
  userId: string;
  socket: WebSocket;
  lanAddress?: string;
  battery?: number;
}

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

  /** Push a JSON message to a device if it is online. Returns whether it was delivered. */
  sendTo(deviceId: string, message: unknown): boolean {
    const conn = byDevice.get(deviceId);
    if (!conn) return false;
    conn.socket.send(JSON.stringify(message));
    return true;
  },
};
