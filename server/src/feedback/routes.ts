import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { allowWebsite, websitePreflight } from '../http/website-cors.js';
import { emit } from '../jobs/inngest.js';

/** A bug report or idea from the website's /report form. Limits keep one report readable. */
export const feedbackSchema = z.object({
  kind: z.enum(['bug', 'idea', 'other']),
  platform: z.enum(['mac', 'android', 'both', 'website']),
  message: z.string().trim().min(10).max(5000),
  steps: z.string().trim().max(5000).optional(),
  appVersion: z.string().trim().max(40).optional(),
  // Optional, for a reply. The email goes out with it as Reply-To.
  email: z.string().trim().email().max(200).optional().or(z.literal('')),
  // A field people never see: a bot that fills every input fills this one too.
  website: z.string().max(500).optional(),
});

export type Feedback = z.infer<typeof feedbackSchema>;

// ponytail: per-IP count in this process's memory (one server); a shared store if it scales out.
const WINDOW_MS = 60 * 60 * 1000;
const PER_WINDOW = 5;
const recent = new Map<string, number[]>();

function allowed(ip: string, now = Date.now()): boolean {
  const times = (recent.get(ip) ?? []).filter((t) => now - t < WINDOW_MS);
  if (times.length >= PER_WINDOW) return false;
  times.push(now);
  recent.set(ip, times);
  return true;
}

export function registerFeedbackRoutes(app: FastifyInstance): void {
  websitePreflight(app, '/feedback');

  app.post('/feedback', async (request, reply) => {
    allowWebsite(request, reply);
    const parsed = feedbackSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: {
          code: 'invalid_request',
          message: 'Tell us what happened in at least a sentence (10 characters or more).',
        },
      });
    }
    if (!allowed(request.ip)) {
      return reply.status(429).send({
        error: {
          code: 'rate_limited',
          message: 'Thanks — that is a lot of reports. Try again in an hour.',
        },
      });
    }
    // A filled honeypot is a bot: answer as if it worked, send nothing.
    if (parsed.data.website) return reply.send({ ok: true });
    const { kind, platform, message, steps, appVersion, email } = parsed.data;
    emit({
      name: 'feedback/submitted',
      data: { kind, platform, message, steps, appVersion, email: email || undefined },
    });
    return reply.send({ ok: true });
  });
}
