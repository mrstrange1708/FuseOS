import { and, eq, isNull } from 'drizzle-orm';
import type { FastifyInstance } from 'fastify';
import { randomBytes } from 'node:crypto';
import { z } from 'zod';
import { authenticate } from '../auth/session.js';
import { getDb } from '../db/client.js';
import { isUniqueViolation } from '../db/errors.js';
import { deviceTrust, devices, pairingCodes, type Device } from '../db/schema.js';
import { presence } from '../signal/presence.js';

// 8 uppercase alphanumerics, shown grouped as XXXX-XXXX. The alphabet omits the
// visually ambiguous I, O, 0, 1 so a code is easy to read off one screen and type
// on another.
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const CODE_LENGTH = 8;
const CODE_TTL_MS = 5 * 60 * 1000;

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

const initiateSchema = z.object({ deviceId: z.string().uuid() });
const claimSchema = z.object({ deviceId: z.string().uuid(), code: z.string().min(6).max(20) });

type ClaimResult =
  | { ok: true; initiator: Device; claimer: Device }
  | { ok: false; status: number; code: string; message: string };

export function registerPairingRoutes(app: FastifyInstance): void {
  // Device A asks for a code to show on screen.
  app.post('/pairing/initiate', { preHandler: authenticate }, async (request, reply) => {
    const userId = request.userId;
    if (!userId) return;
    const parsed = initiateSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: { code: 'invalid_request', message: 'Provide the deviceId to pair.' },
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

    const expiresAt = new Date(Date.now() + CODE_TTL_MS);
    // Retry on the (astronomically unlikely) collision with another active code.
    for (let attempt = 0; attempt < 5; attempt++) {
      const code = generateCode();
      try {
        await getDb().insert(pairingCodes).values({ userId, deviceId: device.id, code, expiresAt });
        return reply.status(201).send({ code: grouped(code), expiresAt: expiresAt.toISOString() });
      } catch (error) {
        if (isUniqueViolation(error)) continue;
        throw error;
      }
    }
    return reply
      .status(500)
      .send({ error: { code: 'internal', message: 'Could not allocate a code — try again.' } });
  });

  // Device B redeems the code; on success the two devices are trusted.
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

    const result = await getDb().transaction(async (tx): Promise<ClaimResult> => {
      const [row] = await tx
        .select()
        .from(pairingCodes)
        .where(
          and(
            eq(pairingCodes.userId, userId),
            eq(pairingCodes.code, code),
            isNull(pairingCodes.usedAt),
          ),
        )
        .limit(1)
        .for('update');
      if (!row)
        return { ok: false, status: 404, code: 'code_invalid', message: 'That code is not valid.' };
      if (row.expiresAt.getTime() <= Date.now()) {
        return { ok: false, status: 410, code: 'code_expired', message: 'That code has expired.' };
      }
      const initiatorId = row.deviceId;
      if (initiatorId === claimerId) {
        return {
          ok: false,
          status: 400,
          code: 'same_device',
          message: 'Enter the code on your other device.',
        };
      }

      const [claimer] = await tx
        .select()
        .from(devices)
        .where(and(eq(devices.id, claimerId), eq(devices.userId, userId)))
        .limit(1);
      if (!claimer) {
        return { ok: false, status: 404, code: 'device_not_found', message: 'Unknown device.' };
      }
      const [initiator] = await tx
        .select()
        .from(devices)
        .where(eq(devices.id, initiatorId))
        .limit(1);
      if (!initiator) {
        return {
          ok: false,
          status: 404,
          code: 'device_not_found',
          message: 'The other device no longer exists.',
        };
      }

      // device_trust stores each pair once, canonically ordered (device_a < device_b).
      const [lo, hi] =
        initiatorId < claimerId ? [initiatorId, claimerId] : [claimerId, initiatorId];
      await tx.insert(deviceTrust).values({ deviceA: lo, deviceB: hi }).onConflictDoNothing();
      await tx.update(pairingCodes).set({ usedAt: new Date() }).where(eq(pairingCodes.id, row.id));
      return { ok: true, initiator, claimer };
    });

    if (!result.ok) {
      return reply
        .status(result.status)
        .send({ error: { code: result.code, message: result.message } });
    }

    // Notify the initiator over /signal that the pairing completed (best-effort;
    // durable delivery becomes an Inngest job later — see docs/api.md).
    presence.sendTo(result.initiator.id, {
      type: 'paired',
      deviceId: result.claimer.id,
      name: result.claimer.name,
      platform: result.claimer.platform,
      publicKey: result.claimer.publicKey,
    });

    return reply.send({
      trustedWith: {
        deviceId: result.initiator.id,
        name: result.initiator.name,
        platform: result.initiator.platform,
        publicKey: result.initiator.publicKey,
      },
    });
  });
}
