import { describe, expect, it } from 'vitest';
import { buildApp } from '../app.js';
import { feedbackReport } from '../email/templates.js';

const report = { kind: 'bug', platform: 'mac', message: 'Clipboard stopped syncing after sleep.' };

describe('/feedback', () => {
  const post = (payload: Record<string, unknown>, ip: string) =>
    buildApp().inject({ method: 'POST', url: '/feedback', payload, remoteAddress: ip });

  it('takes a report', async () => {
    const res = await post(
      { ...report, email: 'someone@example.com', steps: '1. sleep 2. wake' },
      '10.0.0.1',
    );
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ ok: true });
  });

  it('refuses one too short to act on', async () => {
    const res = await post({ ...report, message: 'broken' }, '10.0.0.2');
    expect(res.statusCode).toBe(400);
  });

  it('answers a bot (honeypot filled) as if it worked', async () => {
    const res = await post({ ...report, website: 'http://spam.example' }, '10.0.0.3');
    expect(res.statusCode).toBe(200);
  });

  it('allows five an hour from one address', async () => {
    for (let i = 0; i < 5; i++) expect((await post(report, '10.0.0.4')).statusCode).toBe(200);
    expect((await post(report, '10.0.0.4')).statusCode).toBe(429);
    expect((await post(report, '10.0.0.5')).statusCode).toBe(200);
  });

  it('lets only the website post from a browser', async () => {
    const preflight = (origin: string) =>
      buildApp().inject({ method: 'OPTIONS', url: '/feedback', headers: { origin } });
    expect((await preflight('https://fuseos.theshaik.dev')).statusCode).toBe(204);
    expect((await preflight('https://evil.example')).statusCode).toBe(403);
  });
});

describe('the report email', () => {
  it('escapes what the reporter typed', () => {
    const email = feedbackReport({
      kind: 'bug',
      platform: 'android',
      message: '<img src=x onerror=alert(1)> it crashed',
    });
    expect(email.html).not.toContain('<img src=x');
    expect(email.html).toContain('&lt;img src=x onerror=alert(1)&gt;');
    expect(email.subject).toBe('[FuseOS bug] <img src=x onerror=alert(1)> it crashed');
  });
});
