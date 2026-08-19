import { and, eq } from 'drizzle-orm';
import type { FastifyInstance } from 'fastify';
import { randomBytes } from 'node:crypto';
import { z } from 'zod';
import { authenticate } from '../auth/session.js';
import { getDb } from '../db/client.js';
import { devices, type Device } from '../db/schema.js';
import { presence } from '../signal/presence.js';

/**
 * Manual linking — the safety net behind automatic linking.
 *
 * Two devices on one account are already trusted (see devices/trust.ts), so a code cannot
 * grant trust and this is deliberately not a trust flow. What it does is **force an
 * introduction**: claiming a code returns the other device's peer card — public key and
 * last known LAN address — and pushes this device's card back over `/signal`. That is
 * exactly what `hello`/`peer-online` normally deliver on their own, so the code is the
 * hand-crank for when they haven't: a socket that dropped, presence that went stale, a
 * device the other side simply hasn't heard about yet.
 *
 * Both devices must be on the caller's account. A code is never a way to reach a stranger.
 */

// 8 uppercase alphanumerics, shown grouped as XXXX-XXXX. The alphabet omits the
// visually ambiguous I, O, 0, 1 so a code is easy to read off one screen and type
// on another.
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const CODE_LENGTH = 8;
const CODE_TTL_MS = 5 * 60 * 1000;

interface PendingCode {
  userId: string;
  deviceId: string;
  expiresAt: number;
}

/**
 * Live codes, keyed by code.
 *
 * ponytail: in memory rather than a `pairing_codes` table. A code lives five minutes and
 * means nothing after it is claimed, so persisting it buys only survival across a restart
 * — at the cost of a table, a migration, and an expiry job. Presence is in-memory for the
 * same reason. Move both to Redis if the control plane ever runs more than one instance;
 * until then a restart just means the user presses the button again.
 */
const codes = new Map<string, PendingCode>();

function sweepExpired(now: number): void {
  for (const [code, pending] of codes) {
    if (pending.expiresAt <= now) codes.delete(code);
  }
}

function generateCode(): string {
  let out = '';
  for (const byte of randomBytes(CODE_LENGTH)) {
    out += CODE_ALPHABET[byte % CODE_ALPHABET.length] ?? '';
  }
  return out;
}

/** "A7X29QKM" -> "A7X2-9QKM" for display. */
function grouped(code: string): string {
  return `${code.slice(0, 4)}-${code.slice(4)}`;
}

/** Strip formatting/case so "a7x2-9qkm" matches the stored "A7X29QKM". */
function normalizeCode(input: string): string {
  return input.toUpperCase().replace(/[^A-Z0-9]/g, '');
}

/** The peer card a device needs to dial another: who to trust, and where to reach it. */
function card(device: Device) {
  const conn = presence.get(device.id);
  return {
    deviceId: device.id,
    name: device.name,
    platform: device.platform,
    publicKey: device.publicKey,
    lanAddress: conn?.lanAddress ?? null,
  };
}

const initiateSchema = z.object({ deviceId: z.string().uuid() });
const claimSchema = z.object({ deviceId: z.string().uuid(), code: z.string().min(6).max(20) });

export function registerPairingRoutes(app: FastifyInstance): void {
  // Device A asks for a code to show on screen (and encode as a QR).
  app.post('/pairing/initiate', { preHandler: authenticate }, async (request, reply) => {
    const userId = request.userId;
    if (!userId) return;
    const parsed = initiateSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: { code: 'invalid_request', message: 'Provide the deviceId to link.' },
      });
    }
    const [device] = await getDb()
      .select()
      .from(devices)
      .where(and(eq(devices.id, parsed.data.deviceId), eq(devices.userId, userId)))
      .limit(1);
    if (!device) {
      return reply
        .status(404)
        .send({ error: { code: 'device_not_found', message: 'Unknown device.' } });
    }

    const now = Date.now();
    sweepExpired(now);
    // Retry on the (astronomically unlikely) collision with another live code.
    for (let attempt = 0; attempt < 5; attempt++) {
      const code = generateCode();
      if (codes.has(code)) continue;
      const expiresAt = now + CODE_TTL_MS;
      codes.set(code, { userId, deviceId: device.id, expiresAt });
      return reply.status(201).send({
        code: grouped(code),
        expiresAt: new Date(expiresAt).toISOString(),
      });
    }
    return reply
      .status(500)
      .send({ error: { code: 'internal', message: 'Could not allocate a code — try again.' } });
  });

  // Device B redeems the code; both ends get the other's peer card.
  app.post('/pairing/claim', { preHandler: authenticate }, async (request, reply) => {
    const userId = request.userId;
    if (!userId) return;
    const parsed = claimSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: { code: 'invalid_request', message: 'Provide your deviceId and the code.' },
      });
    }
    const claimerId = parsed.data.deviceId;
    const code = normalizeCode(parsed.data.code);
    const now = Date.now();
    sweepExpired(now);

    const pending = codes.get(code);
    // Same-account only. A code from another account reads as invalid rather than
    // forbidden: whether a code exists elsewhere is not this caller's business.
    if (!pending || pending.userId !== userId) {
      return reply
        .status(404)
        .send({ error: { code: 'code_invalid', message: 'That code is not valid.' } });
    }
    if (pending.deviceId === claimerId) {
      return reply.status(400).send({
        error: { code: 'same_device', message: 'Enter the code on your other device.' },
      });
    }

    const [claimer] = await getDb()
      .select()
      .from(devices)
      .where(and(eq(devices.id, claimerId), eq(devices.userId, userId)))
      .limit(1);
    if (!claimer) {
      return reply
        .status(404)
        .send({ error: { code: 'device_not_found', message: 'Unknown device.' } });
    }
    const [initiator] = await getDb()
      .select()
      .from(devices)
      .where(eq(devices.id, pending.deviceId))
      .limit(1);
    if (!initiator) {
      return reply.status(404).send({
        error: { code: 'device_not_found', message: 'The other device no longer exists.' },
      });
    }

    // One-time: a claimed code is spent, so a shoulder-surfed code cannot be replayed.
    codes.delete(code);

    // Push the claimer's card to the initiator, which is the half it cannot ask for.
    // Best-effort — if that socket is down, the initiator picks the claimer up on its
    // next `hello` anyway.
    presence.sendTo(initiator.id, { type: 'peer-online', ...card(claimer) });

    return reply.send({ trustedWith: card(initiator) });
  });
}
