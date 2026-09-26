import { and, eq } from 'drizzle-orm';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { authenticate } from '../auth/session.js';
import { getDb } from '../db/client.js';
import { devices } from '../db/schema.js';
import { presence } from '../signal/presence.js';

const registerSchema = z.object({
  name: z.string().trim().min(1).max(100),
  platform: z.enum(['android', 'macos']),
  publicKey: z.string().trim().min(1).max(1000),
  battery: z.number().int().min(0).max(100).optional(),
});

const deviceParamsSchema = z.object({ id: z.string().uuid() });

const listQuerySchema = z.object({
  // The caller's own device id, so we can flag which row is itself.
  self: z.string().uuid().optional(),
});

export function registerDeviceRoutes(app: FastifyInstance): void {
  // Register (or re-register) this device. Idempotent by public key so a client
  // can call it on every launch and always get back its stable device id.
  app.post('/devices', { preHandler: authenticate }, async (request, reply) => {
    const userId = request.userId;
    if (!userId) return;
    const parsed = registerSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: {
          code: 'invalid_request',
          message: 'Provide a device name, platform (android|macos), and public key.',
        },
      });
    }
    const now = new Date();
    // Upsert by public key, but only ever update a row the caller already owns
    // (`setWhere`). A public key registered to another account must NOT be
    // reassigned — that would let anyone who learns a (non-secret) device public
    // key take over that device. Such a conflict updates 0 rows → 409.
    const [device] = await getDb()
      .insert(devices)
      .values({
        userId,
        name: parsed.data.name,
        platform: parsed.data.platform,
        publicKey: parsed.data.publicKey,
        battery: parsed.data.battery ?? null,
        lastSeen: now,
      })
      .onConflictDoUpdate({
        target: devices.publicKey,
        set: {
          name: parsed.data.name,
          platform: parsed.data.platform,
          // Only overwrite battery when the client actually reported one. This runs on
          // every launch, and a re-register that omits it must not erase the last known
          // level — the dashboard would show a peer's battery blanking out for no reason.
          ...(parsed.data.battery !== undefined ? { battery: parsed.data.battery } : {}),
          lastSeen: now,
        },
        setWhere: eq(devices.userId, userId),
      })
      .returning();
    if (!device) {
      return reply.status(409).send({
        error: {
          code: 'public_key_taken',
          message: 'This device key is already registered to another account.',
        },
      });
    }
    return reply.status(201).send({
      id: device.id,
      name: device.name,
      platform: device.platform,
      createdAt: device.createdAt,
    });
  });

  // List the caller's devices with live presence + battery (for the dashboard).
  app.get('/devices', { preHandler: authenticate }, async (request, reply) => {
    const userId = request.userId;
    if (!userId) return;
    const parsed = listQuerySchema.safeParse(request.query);
    if (!parsed.success) {
      return reply.status(400).send({
        error: { code: 'invalid_request', message: 'Invalid query parameters.' },
      });
    }
    const rows = await getDb().select().from(devices).where(eq(devices.userId, userId));

    const list = rows.map((device) => {
      const conn = presence.get(device.id);
      return {
        id: device.id,
        name: device.name,
        platform: device.platform,
        online: presence.isOnline(device.id),
        // Prefer the live value from an open socket, else the last persisted one.
        battery: conn?.battery ?? device.battery ?? null,
        lastSeen: device.lastSeen,
        // Every other device on the account is trusted (see devices/trust.ts) — but
        // "other" needs a reference point, so without ?self= nothing is flagged.
        trusted: parsed.data.self !== undefined && parsed.data.self !== device.id,
        isSelf: parsed.data.self === device.id,
      };
    });
    return reply.send({ devices: list });
  });

  // Remove one of the caller's devices — the stale record a reinstall leaves behind.
  // Only offline devices: a live one is signed out on the device itself, not from afar.
  app.delete('/devices/:id', { preHandler: authenticate }, async (request, reply) => {
    const userId = request.userId;
    if (!userId) return;
    const parsed = deviceParamsSchema.safeParse(request.params);
    if (!parsed.success) {
      return reply.status(400).send({
        error: { code: 'invalid_request', message: 'Invalid device id.' },
      });
    }
    if (presence.isOnline(parsed.data.id)) {
      return reply.status(409).send({
        error: {
          code: 'device_online',
          message: 'That device is online. Sign out on it instead.',
        },
      });
    }
    const removed = await getDb()
      .delete(devices)
      .where(and(eq(devices.id, parsed.data.id), eq(devices.userId, userId)))
      .returning({ id: devices.id });
    // Another account's device reads as not found: whether it exists is not our business.
    if (removed.length === 0) {
      return reply.status(404).send({
        error: { code: 'device_not_found', message: 'No such device on this account.' },
      });
    }
    return reply.status(204).send();
  });
}
