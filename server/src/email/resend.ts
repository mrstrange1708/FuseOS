import { env } from '../config/env.js';

/**
 * Sends one email through Resend's HTTP API — a single POST, so no SDK. Throws on any
 * failure: callers run inside an Inngest step, which retries. Account email only, never a
 * user payload (CLAUDE.md principle 6).
 */
export async function sendEmail(message: {
  to: string;
  subject: string;
  text: string;
}): Promise<void> {
  if (!env.RESEND_API_KEY) throw new Error('RESEND_API_KEY is not set');
  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      authorization: `Bearer ${env.RESEND_API_KEY}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      from: env.EMAIL_FROM,
      to: [message.to],
      subject: message.subject,
      text: message.text,
    }),
  });
  if (!response.ok) throw new Error(`Resend answered ${response.status}: ${await response.text()}`);
}
