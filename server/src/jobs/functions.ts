import { and, count, eq } from 'drizzle-orm';
import { NonRetriableError } from 'inngest';
import { z } from 'zod';
import { env } from '../config/env.js';
import { getDb } from '../db/client.js';
import { devices, user } from '../db/schema.js';
import { sendEmail } from '../email/resend.js';
import { closeSilentSockets } from '../signal/presence.js';
import { inngest } from './inngest.js';

/**
 * `presence/sweep-timeouts`: every minute, closes /signal sockets that stopped talking.
 * A phone that drops off Wi-Fi without a FIN otherwise stays "online" until TCP gives up
 * (hours). Closing runs the socket's own close handler, so peers get `peer-offline`.
 */
export const sweepPresence = inngest.createFunction(
  { id: 'presence-sweep-timeouts', triggers: [{ cron: '* * * * *' }] },
  async ({ step }) => step.run('close silent sockets', () => ({ closed: closeSilentSockets() })),
);

// The event carries the user id, not the address: the email is read here, at send time.
const verificationRequested = z.object({ userId: z.string().min(1), url: z.string().url() });

/** `auth/send-verification`: the link Better Auth made at sign-up, by email. */
export const sendVerification = inngest.createFunction(
  { id: 'auth-send-verification', triggers: [{ event: 'auth/verification.requested' }] },
  async ({ event, step }) => {
    const parsed = verificationRequested.safeParse(event.data);
    if (!parsed.success) throw new NonRetriableError('malformed auth/verification.requested event');
    const { userId, url } = parsed.data;
    return step.run('send the email', async () => {
      if (!env.RESEND_API_KEY) throw new NonRetriableError('RESEND_API_KEY is not set');
      const [row] = await getDb()
        .select({ email: user.email, name: user.name, verified: user.emailVerified })
        .from(user)
        .where(eq(user.id, userId));
      if (!row) throw new NonRetriableError('the account no longer exists');
      if (row.verified) return { skipped: 'already verified' };
      await sendEmail({
        to: row.email,
        subject: 'Confirm your email for FuseOS',
        text: `Hi ${row.name},\n\nConfirm this is your email for FuseOS:\n${url}\n\nThe link works for one hour. If you didn't create a FuseOS account, ignore this email.\n`,
      });
      return { sent: true };
    });
  },
);

const DOWNLOADS = 'https://github.com/mrstrange1708/FuseOS/releases/latest';

/** A confirmed account's email, or null: nothing is sent to an address nobody confirmed. */
async function confirmedEmail(userId: string): Promise<{ email: string; name: string } | null> {
  const [row] = await getDb()
    .select({ email: user.email, name: user.name, verified: user.emailVerified })
    .from(user)
    .where(eq(user.id, userId));
  return row?.verified ? { email: row.email, name: row.name } : null;
}

const userEvent = z.object({ userId: z.string().min(1) });

/** `auth/welcome`: once the email is confirmed, how to get going on both devices. */
export const sendWelcome = inngest.createFunction(
  { id: 'auth-welcome', triggers: [{ event: 'auth/email.verified' }] },
  async ({ event, step }) => {
    const parsed = userEvent.safeParse(event.data);
    if (!parsed.success) throw new NonRetriableError('malformed auth/email.verified event');
    const { userId } = parsed.data;
    return step.run('send the email', async () => {
      if (!env.RESEND_API_KEY) throw new NonRetriableError('RESEND_API_KEY is not set');
      const to = await confirmedEmail(userId);
      if (!to) return { skipped: 'not confirmed' };
      await sendEmail({
        to: to.email,
        subject: 'Welcome to FuseOS',
        text: `Hi ${to.name},\n\nYour FuseOS account is ready. Sign in with it on your Mac and your Android phone, on the same Wi-Fi, and they link themselves — copy on one, paste on the other.\n\nDownloads (Mac and Android): ${DOWNLOADS}\n\nThe FuseOS team\n`,
      });
      return { sent: true };
    });
  },
);

const deviceEvent = z.object({ userId: z.string().min(1), deviceId: z.string().uuid() });

/**
 * `devices/new-device-alert`: every device on an account is trusted with its clipboard, files
 * and notifications, so the owner hears about each new one — the first device is the sign-up
 * itself and is not news.
 */
export const alertNewDevice = inngest.createFunction(
  { id: 'devices-new-device-alert', triggers: [{ event: 'devices/device.added' }] },
  async ({ event, step }) => {
    const parsed = deviceEvent.safeParse(event.data);
    if (!parsed.success) throw new NonRetriableError('malformed devices/device.added event');
    const { userId, deviceId } = parsed.data;
    return step.run('send the email', async () => {
      if (!env.RESEND_API_KEY) throw new NonRetriableError('RESEND_API_KEY is not set');
      const [total] = await getDb()
        .select({ n: count() })
        .from(devices)
        .where(eq(devices.userId, userId));
      if ((total?.n ?? 0) < 2) return { skipped: 'first device' };
      const [device] = await getDb()
        .select({ name: devices.name, platform: devices.platform })
        .from(devices)
        .where(and(eq(devices.id, deviceId), eq(devices.userId, userId)));
      const to = await confirmedEmail(userId);
      if (!device || !to) return { skipped: device ? 'not confirmed' : 'device gone' };
      const kind = device.platform === 'macos' ? 'Mac' : 'Android phone';
      await sendEmail({
        to: to.email,
        subject: `New device on your FuseOS account: ${device.name}`,
        text: `Hi ${to.name},\n\nA ${kind} named "${device.name}" just signed in to your FuseOS account. Devices on one account share their clipboard, files and notifications.\n\nIf this was you, there's nothing to do. If not, change your password and remove the device in FuseOS → Devices.\n\nThe FuseOS team\n`,
      });
      return { sent: true };
    });
  },
);

export const functions = [sweepPresence, sendVerification, sendWelcome, alertNewDevice];
