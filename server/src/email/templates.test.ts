import { describe, expect, it } from 'vitest';
import * as templates from './templates.js';

describe('email templates', () => {
  it('escapes anything a person typed, in the HTML', () => {
    const email = templates.newDevice('<b>Eve</b>', '<script>x()</script>', 'Mac');
    expect(email.html).not.toContain('<script>x()');
    expect(email.html).toContain('&lt;script&gt;x()&lt;/script&gt;');
    expect(email.html).toContain('&lt;b&gt;Eve&lt;/b&gt;');
    // The text version is plain text: it carries the name as typed.
    expect(email.text).toContain('<script>x()</script>');
  });

  it('puts the link in both versions', () => {
    const url = 'https://fuseos-api.theshaik.dev/auth/reset?token=abc';
    for (const email of [templates.resetPassword('Sam', url), templates.verifyEmail('Sam', url)]) {
      expect(email.html).toContain(`href="${url}"`);
      expect(email.text).toContain(url);
    }
  });

  it('gives release emails an unsubscribe link, and only release emails', () => {
    const release = templates.release('1.2.0', 'https://github.com/x/y/releases/tag/v1.2.0');
    expect(release.subject).toBe('FuseOS 1.2.0 is out');
    expect(release.html).toContain('{{{RESEND_UNSUBSCRIBE_URL}}}');
    expect(release.text).toContain('{{{RESEND_UNSUBSCRIBE_URL}}}');
    expect(templates.welcome('Sam').html).not.toContain('RESEND_UNSUBSCRIBE_URL');
  });
});
