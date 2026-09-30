import { and, count, eq } from 'drizzle-orm';
import { NonRetriableError } from 'inngest';
import { z } from 'zod';
import { env } from '../config/env.js';
import { getDb } from '../db/client.js';
import { devices, user } from '../db/schema.js';
import { addToReleaseList, broadcast, sendEmail } from '../email/resend.js';
import * as templates from '../email/templates.js';
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

function requireResend(): void {
  if (!env.RESEND_API_KEY) throw new NonRetriableError('RESEND_API_KEY is not set');
}

/** The account's address and name, read at send time: events carry ids, never addresses. */
async function account(
  userId: string,
): Promise<{ email: string; name: string; verified: boolean } | null> {
  const [row] = await getDb()
    .select({ email: user.email, name: user.name, verified: user.emailVerified })
    .from(user)
    .where(eq(user.id, userId));
  return row ?? null;
}

function parse<T>(schema: z.ZodType<T>, data: unknown, event: string): T {
  const parsed = schema.safeParse(data);
  if (!parsed.success) throw new NonRetriableError(`malformed ${event} event`);
  return parsed.data;
}

const linkEvent = z.object({ userId: z.string().min(1), url: z.string().url() });
const userEvent = z.object({ userId: z.string().min(1) });
const deviceEvent = z.object({ userId: z.string().min(1), deviceId: z.string().uuid() });
const releaseEvent = z.object({
  version: z.string().min(1).max(40),
  notesUrl: z.string().url(),
});

/** `auth/send-verification`: the confirmation link Better Auth made at sign-up. */
export const sendVerification = inngest.createFunction(
  { id: 'auth-send-verification', triggers: [{ event: 'auth/verification.requested' }] },
  async ({ event, step }) => {
    const { userId, url } = parse(linkEvent, event.data, 'auth/verification.requested');
    return step.run('send the email', async () => {
      requireResend();
      const to = await account(userId);
      if (!to) throw new NonRetriableError('the account no longer exists');
      if (to.verified) return { skipped: 'already verified' };
      await sendEmail(to.email, templates.verifyEmail(to.name, url));
      return { sent: true };
    });
  },
);

/**
 * `auth/welcome`: once the email is confirmed — how to get going, and a place on the release
 * list (Resend keeps the unsubscribe; skipped until RESEND_SEGMENT_ID is set).
 */
export const sendWelcome = inngest.createFunction(
  { id: 'auth-welcome', triggers: [{ event: 'auth/email.verified' }] },
  async ({ event, step }) => {
    const { userId } = parse(userEvent, event.data, 'auth/email.verified');
    const to = await step.run('read the account', () => account(userId));
    if (!to?.verified) return { skipped: 'not confirmed' };
    await step.run('send the email', async () => {
      requireResend();
      await sendEmail(to.email, templates.welcome(to.name));
    });
    if (env.RESEND_SEGMENT_ID) {
      await step.run('join the release list', () => addToReleaseList(to.email, to.name));
    }
    return { sent: true, releaseList: Boolean(env.RESEND_SEGMENT_ID) };
  },
);

/**
 * `devices/new-device-alert`: every device on an account is trusted with its clipboard, files
 * and notifications, so the owner hears about each new one — the first device is the sign-up
 * itself and is not news.
 */
export const alertNewDevice = inngest.createFunction(
  { id: 'devices-new-device-alert', triggers: [{ event: 'devices/device.added' }] },
  async ({ event, step }) => {
    const { userId, deviceId } = parse(deviceEvent, event.data, 'devices/device.added');
    return step.run('send the email', async () => {
      requireResend();
      const [total] = await getDb()
        .select({ n: count() })
        .from(devices)
        .where(eq(devices.userId, userId));
      if ((total?.n ?? 0) < 2) return { skipped: 'first device' };
      const [device] = await getDb()
        .select({ name: devices.name, platform: devices.platform })
        .from(devices)
        .where(and(eq(devices.id, deviceId), eq(devices.userId, userId)));
      const to = await account(userId);
      if (!device) return { skipped: 'device gone' };
      if (!to?.verified) return { skipped: 'not confirmed' };
      const kind = device.platform === 'macos' ? 'Mac' : 'Android phone';
      await sendEmail(to.email, templates.newDevice(to.name, device.name, kind));
      return { sent: true };
    });
  },
);

/**
 * `auth/password-reset`: the reset link. Sent whether or not the address was confirmed —
 * only whoever reads that mailbox gets the link, which is the whole check.
 */
export const sendPasswordReset = inngest.createFunction(
  { id: 'auth-password-reset', triggers: [{ event: 'auth/password-reset.requested' }] },
  async ({ event, step }) => {
    const { userId, url } = parse(linkEvent, event.data, 'auth/password-reset.requested');
    return step.run('send the email', async () => {
      requireResend();
      const to = await account(userId);
      if (!to) return { skipped: 'account gone' };
      await sendEmail(to.email, templates.resetPassword(to.name, url));
      return { sent: true };
    });
  },
);

/**
 * `releases/announce`: a published GitHub release (`release.yml` sends the event, with the tag
 * as its id so a re-run cannot email twice) goes out as one Resend Broadcast to the release list.
 */
export const announceRelease = inngest.createFunction(
  { id: 'releases-announce', triggers: [{ event: 'releases/published' }] },
  async ({ event, step }) => {
    const { version, notesUrl } = parse(releaseEvent, event.data, 'releases/published');
    return step.run('send the broadcast', async () => {
      requireResend();
      if (!env.RESEND_SEGMENT_ID) throw new NonRetriableError('RESEND_SEGMENT_ID is not set');
      await broadcast(`FuseOS ${version}`, templates.release(version, notesUrl));
      return { sent: true };
    });
  },
);

const feedbackEvent = z.object({
  kind: z.enum(['bug', 'idea', 'other']),
  platform: z.enum(['mac', 'android', 'both', 'website']),
  message: z.string().min(1).max(5000),
  steps: z.string().max(5000).optional(),
  appVersion: z.string().max(40).optional(),
  email: z.string().email().optional(),
});

/** `feedback/email`: a report from the website's /report form, to the owner (`FEEDBACK_TO`). */
export const emailFeedback = inngest.createFunction(
  { id: 'feedback-email', triggers: [{ event: 'feedback/submitted' }] },
  async ({ event, step }) => {
    const report = parse(feedbackEvent, event.data, 'feedback/submitted');
    return step.run('send the email', async () => {
      requireResend();
      if (!env.FEEDBACK_TO) throw new NonRetriableError('FEEDBACK_TO is not set');
      await sendEmail(env.FEEDBACK_TO, templates.feedbackReport(report), report.email);
      return { sent: true };
    });
  },
);

export const functions = [
  sweepPresence,
  sendVerification,
  sendWelcome,
  alertNewDevice,
  sendPasswordReset,
  announceRelease,
  emailFeedback,
];
