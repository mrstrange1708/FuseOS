import { and, eq, inArray } from 'drizzle-orm';
import type { FastifyInstance } from 'fastify';
import type { IncomingMessage } from 'node:http';
import { WebSocketServer } from 'ws';
import type { RawData, WebSocket } from 'ws';
import { z } from 'zod';
import { userIdForToken } from '../auth/session.js';
import { getDb } from '../db/client.js';
import { devices, type Device } from '../db/schema.js';
import { trustedPeerIds } from '../pairing/trust.js';
import { presence } from './presence.js';

const AUTH_TIMEOUT_MS = 5_000;

const helloSchema = z.object({
  type: z.literal('hello'),
  token: z.string().min(1),
  deviceId: z.string().uuid(),
  lanAddress: z.string().max(100).optional(),
  battery: z.number().int().min(0).max(100).optional(),
});

const heartbeatSchema = z.object({
  type: z.literal('heartbeat'),
  battery: z.number().int().min(0).max(100).optional(),
  lanAddress: z.string().max(100).optional(),
});

function send(socket: WebSocket, message: unknown): void {
  if (socket.readyState === socket.OPEN) socket.send(JSON.stringify(message));
}

function parse(data: RawData): unknown {
  try {
    return JSON.parse(data.toString());
  } catch {
    return null;
  }
}

/** A device's public presence card, sent to its trusted peers. */
function card(device: Device, lanAddress?: string, battery?: number) {
  return {
    deviceId: device.id,
    name: device.name,
    platform: device.platform,
    lanAddress: lanAddress ?? null,
    battery: battery ?? device.battery ?? null,
  };
}

/** Attaches the `/signal` WebSocket to the Fastify HTTP server. Presence + LAN
 *  signaling only — no clipboard/file payloads ever cross this socket. */
export function attachSignal(app: FastifyInstance): void {
  const wss = new WebSocketServer({ noServer: true });

  app.server.on('upgrade', (req: IncomingMessage, socket, head) => {
    const pathname = req.url ? new URL(req.url, 'http://localhost').pathname : '';
    if (pathname !== '/signal') {
      socket.destroy();
      return;
    }
    wss.handleUpgrade(req, socket, head, (ws) => wss.emit('connection', ws, req));
  });

  wss.on('connection', (ws: WebSocket) => {
    let device: Device | null = null;

    // Drop connections that never authenticate.
    const authTimer = setTimeout(() => {
      if (!device) {
        send(ws, { type: 'error', message: 'Authentication timed out.' });
        ws.close();
      }
    }, AUTH_TIMEOUT_MS);

    const broadcastToPeers = async (message: unknown): Promise<void> => {
      if (!device) return;
      const peerIds = await trustedPeerIds(device.id);
      for (const peerId of peerIds) presence.sendTo(peerId, message);
    };

    ws.on('message', (data: RawData) => {
      void (async () => {
        const payload = parse(data);

        if (!device) {
          const hello = helloSchema.safeParse(payload);
          if (!hello.success) {
            send(ws, { type: 'error', message: 'Expected a hello frame with a valid token.' });
            return;
          }
          const userId = await userIdForToken(hello.data.token);
          if (!userId) {
            send(ws, { type: 'error', message: 'Invalid token.' });
            ws.close();
            return;
          }
          const [row] = await getDb()
            .select()
            .from(devices)
            .where(and(eq(devices.id, hello.data.deviceId), eq(devices.userId, userId)))
            .limit(1);
          if (!row) {
            send(ws, { type: 'error', message: 'Unknown device for this account.' });
            ws.close();
            return;
          }

          device = row;
          clearTimeout(authTimer);
          const lanAddress = hello.data.lanAddress;
          const battery = hello.data.battery;
          await getDb()
            .update(devices)
            .set({ lastSeen: new Date(), ...(battery !== undefined ? { battery } : {}) })
            .where(eq(devices.id, device.id));
          presence.add({ deviceId: device.id, userId, socket: ws, lanAddress, battery });

          // Tell the newcomer which trusted peers are already online...
          const peerIds = await trustedPeerIds(device.id);
          const onlinePeerIds = peerIds.filter((id) => presence.isOnline(id));
          const peerRows =
            onlinePeerIds.length > 0
              ? await getDb().select().from(devices).where(inArray(devices.id, onlinePeerIds))
              : [];
          const peers = peerRows.map((peer) => {
            const conn = presence.get(peer.id);
            return { ...card(peer, conn?.lanAddress, conn?.battery), online: true };
          });
          send(ws, { type: 'hello-ok', deviceId: device.id, peers });

          // ...and tell those peers the newcomer is now online.
          const online = card(device, lanAddress, battery);
          for (const peerId of onlinePeerIds) {
            presence.sendTo(peerId, { type: 'peer-online', ...online });
          }
          return;
        }

        const heartbeat = heartbeatSchema.safeParse(payload);
        if (heartbeat.success) {
          const conn = presence.get(device.id);
          if (conn) {
            if (heartbeat.data.battery !== undefined) conn.battery = heartbeat.data.battery;
            if (heartbeat.data.lanAddress !== undefined)
              conn.lanAddress = heartbeat.data.lanAddress;
          }
          const battery = heartbeat.data.battery;
          await getDb()
            .update(devices)
            .set({ lastSeen: new Date(), ...(battery !== undefined ? { battery } : {}) })
            .where(eq(devices.id, device.id));
          if (battery !== undefined) {
            await broadcastToPeers({ type: 'peer-update', deviceId: device.id, battery });
          }
        }
      })();
    });

    ws.on('close', () => {
      clearTimeout(authTimer);
      if (!device) return;
      const closed = device;
      presence.remove(closed.id, ws);
      void broadcastToPeers({ type: 'peer-offline', deviceId: closed.id });
    });

    ws.on('error', () => {
      // Fail soft: a socket error just drops the connection; `close` handles cleanup.
    });
  });
}
