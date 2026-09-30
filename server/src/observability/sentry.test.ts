import { describe, expect, it } from 'vitest';
import { scrub } from './sentry.js';

describe('sentry scrub', () => {
  it('keeps the route and drops the query, body, headers and cookies', () => {
    const event = scrub({
      type: undefined,
      request: {
        method: 'GET',
        url: 'https://fuseos-api.theshaik.dev/auth/verify-email?token=secret',
        query_string: 'token=secret',
        data: { password: 'hunter2' },
        headers: { authorization: 'Bearer secret' },
        cookies: { session: 'secret' },
      },
      breadcrumbs: [{ category: 'http', data: { url: 'https://api.resend.com/x?key=secret' } }],
    });
    expect(event.request).toEqual({
      method: 'GET',
      url: 'https://fuseos-api.theshaik.dev/auth/verify-email',
    });
    expect(JSON.stringify(event)).not.toContain('secret');
  });
});
