import { env } from '../config/env.js';
import type { Email } from './templates.js';

/**
 * Resend's HTTP API — a few POSTs, so no SDK. Everything throws on failure: callers run
 * inside Inngest steps, which retry. Account email only, never a user payload (CLAUDE.md
 * principle 6).
 */
async function resend(path: string, body: unknown): Promise<Response> {
  if (!env.RESEND_API_KEY) throw new Error('RESEND_API_KEY is not set');
  return fetch(`https://api.resend.com${path}`, {
    method: 'POST',
    headers: { authorization: `Bearer ${env.RESEND_API_KEY}`, 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
}

async function expectOk(response: Response): Promise<void> {
  if (!response.ok) throw new Error(`Resend answered ${response.status}: ${await response.text()}`);
}

/** One email to one person: HTML, with the text version for clients that want it. */
export async function sendEmail(to: string, email: Email, replyTo?: string): Promise<void> {
  await expectOk(
    await resend('/emails', {
      from: env.EMAIL_FROM,
      to: [to],
      subject: email.subject,
      html: email.html,
      text: email.text,
      ...(replyTo ? { reply_to: replyTo } : {}),
    }),
  );
}

/**
 * Puts a confirmed user on the release list (the Resend segment `RESEND_SEGMENT_ID`), where
 * Resend keeps their unsubscribe choice. Already there is fine.
 */
export async function addToReleaseList(email: string, firstName: string): Promise<void> {
  if (!env.RESEND_SEGMENT_ID) throw new Error('RESEND_SEGMENT_ID is not set');
  const response = await resend('/contacts', {
    email,
    first_name: firstName,
    segments: [{ id: env.RESEND_SEGMENT_ID }],
  });
  if (response.status === 409 || response.status === 422) {
    const detail = await response.text();
    if (/already exists/i.test(detail)) return;
    throw new Error(`Resend answered ${response.status}: ${detail}`);
  }
  await expectOk(response);
}

/** Emails the whole release list at once; Resend skips anyone who unsubscribed. */
export async function broadcast(name: string, email: Email): Promise<void> {
  if (!env.RESEND_SEGMENT_ID) throw new Error('RESEND_SEGMENT_ID is not set');
  await expectOk(
    await resend('/broadcasts', {
      segment_id: env.RESEND_SEGMENT_ID,
      from: env.EMAIL_FROM,
      subject: email.subject,
      html: email.html,
      text: email.text,
      name,
      send: true,
    }),
  );
}
