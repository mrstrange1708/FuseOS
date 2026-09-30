/**
 * Every FuseOS email, as HTML and plain text. Without HTML, Resend sends the bare text; with
 * it, clients show the branded card and fall back to the text version.
 *
 * Styles are inline and the layout is tables: mail clients (Gmail, Outlook) drop <style>
 * blocks and most modern CSS, and a table is what renders the same everywhere. Light card
 * on a light page — dark backgrounds get inverted unpredictably by clients' dark modes.
 *
 * Anything a person typed (their name, a device name) goes through `escape`, so it can only
 * ever be text in the email, never markup.
 */

export interface Email {
  subject: string;
  html: string;
  text: string;
}

const EMBER = '#ff6a3d';
const INK = '#14161c';
const MUTED = '#5b6270';
const SITE = 'https://fuseos.theshaik.dev';

export function escape(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

interface Layout {
  /** Shown by inboxes next to the subject. */
  preheader: string;
  heading: string;
  /** Plain sentences; each becomes a paragraph. Escaped here. */
  paragraphs: string[];
  button?: { label: string; url: string };
  /** Small print under the button. Escaped here. */
  note?: string;
  /** Raw HTML footer line (already safe), e.g. an unsubscribe link. */
  footerHtml?: string;
  footerText?: string;
}

function render(layout: Layout): { html: string; text: string } {
  const paragraphs = layout.paragraphs
    .map(
      (p) =>
        `<p style="margin:0 0 16px;font-size:16px;line-height:1.6;color:${INK};">${escape(p)}</p>`,
    )
    .join('');
  const button = layout.button
    ? `<table role="presentation" cellpadding="0" cellspacing="0" style="margin:8px 0 24px;"><tr><td style="border-radius:10px;background:${EMBER};">` +
      `<a href="${escape(layout.button.url)}" style="display:inline-block;padding:13px 24px;font-size:15px;font-weight:600;color:#ffffff;text-decoration:none;border-radius:10px;">${escape(layout.button.label)}</a>` +
      `</td></tr></table>`
    : '';
  const note = layout.note
    ? `<p style="margin:0;font-size:13px;line-height:1.6;color:${MUTED};">${escape(layout.note)}</p>`
    : '';
  const footer =
    layout.footerHtml ??
    `You're getting this because you have a FuseOS account. <a href="${SITE}" style="color:${MUTED};">fuseos.theshaik.dev</a>`;

  const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light"><title>${escape(layout.heading)}</title></head>
<body style="margin:0;padding:0;background:#f4f5f7;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
<span style="display:none;max-height:0;overflow:hidden;opacity:0;">${escape(layout.preheader)}</span>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f5f7;padding:32px 16px;"><tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;">
<tr><td style="padding:0 4px 16px;font-size:20px;font-weight:800;letter-spacing:-0.02em;color:${INK};">Fuse<span style="color:${EMBER};">OS</span></td></tr>
<tr><td style="background:#ffffff;border-radius:16px;padding:32px 28px;border-top:4px solid ${EMBER};">
<h1 style="margin:0 0 16px;font-size:22px;line-height:1.3;color:${INK};">${escape(layout.heading)}</h1>
${paragraphs}${button}${note}
</td></tr>
<tr><td style="padding:20px 4px 0;font-size:12px;line-height:1.6;color:${MUTED};">${footer}</td></tr>
</table></td></tr></table></body></html>`;

  const text = [
    layout.heading,
    '',
    ...layout.paragraphs.flatMap((p) => [p, '']),
    ...(layout.button ? [`${layout.button.label}: ${layout.button.url}`, ''] : []),
    ...(layout.note ? [layout.note, ''] : []),
    '— FuseOS',
    layout.footerText ?? SITE,
  ].join('\n');
  return { html, text };
}

const DOWNLOADS = `${SITE}/download`;

export function verifyEmail(name: string, url: string): Email {
  return {
    subject: 'Confirm your email for FuseOS',
    ...render({
      preheader: 'One click to confirm your FuseOS account.',
      heading: 'Confirm your email',
      paragraphs: [
        `Hi ${name},`,
        'Confirm this is your email address for FuseOS. It lets you reset your password and sign in with Google later.',
      ],
      button: { label: 'Confirm email', url },
      note: "The link works for one hour. If you didn't create a FuseOS account, ignore this email.",
    }),
  };
}

export function welcome(name: string): Email {
  return {
    subject: 'Welcome to FuseOS',
    ...render({
      preheader: 'Copy on your phone, paste on your Mac.',
      heading: `Welcome, ${name}`,
      paragraphs: [
        'Your FuseOS account is ready. Sign in with it on your Mac and your Android phone, on the same Wi-Fi, and they link themselves.',
        'Then copy on one and paste on the other, drop files across, see your phone’s notifications on your Mac, and more. Everything travels straight over your Wi-Fi, never through our servers.',
      ],
      button: { label: 'Get the apps', url: DOWNLOADS },
      note: 'Questions or ideas? Reply to this email.',
    }),
  };
}

export function newDevice(name: string, deviceName: string, kind: string): Email {
  return {
    subject: `New device on your FuseOS account: ${deviceName}`,
    ...render({
      preheader: `A ${kind} just signed in to your account.`,
      heading: 'A new device signed in',
      paragraphs: [
        `Hi ${name},`,
        `A ${kind} named “${deviceName}” just signed in to your FuseOS account. Devices on one account share their clipboard, files and notifications.`,
        "If this was you, there's nothing to do. If not, reset your password now and remove the device in FuseOS → Devices.",
      ],
      button: { label: "Wasn't you? Secure your account", url: `${SITE}/help#not-you` },
      note: 'We send this for every new device, so you always know what is linked.',
    }),
  };
}

export function resetPassword(name: string, url: string): Email {
  return {
    subject: 'Reset your FuseOS password',
    ...render({
      preheader: 'Choose a new password for FuseOS.',
      heading: 'Reset your password',
      paragraphs: [
        `Hi ${name},`,
        'Someone asked to reset the password for your FuseOS account. Choose a new one here.',
      ],
      button: { label: 'Choose a new password', url },
      note: "The link works for one hour. Resetting signs every device out, so sign in again with the new password. If you didn't ask for this, ignore this email; your password stays the same.",
    }),
  };
}

/** A new release, to everyone on the release list. Resend fills in the unsubscribe link. */
export function release(version: string, notesUrl: string): Email {
  return {
    subject: `FuseOS ${version} is out`,
    ...render({
      preheader: `What's new in FuseOS ${version}.`,
      heading: `FuseOS ${version} is here`,
      paragraphs: [
        'A new version of FuseOS is ready for your Mac and your Android phone.',
        'Update both so they keep working together: download the new versions and install them over the old ones. Your account, links and history stay as they are.',
      ],
      button: { label: 'Download the update', url: DOWNLOADS },
      note: `What changed: ${notesUrl}`,
      footerHtml: `You're getting this because you use FuseOS. <a href="{{{RESEND_UNSUBSCRIBE_URL}}}" style="color:${MUTED};">Unsubscribe from release emails</a>`,
      footerText: 'Unsubscribe from release emails: {{{RESEND_UNSUBSCRIBE_URL}}}',
    }),
  };
}

const KIND = { bug: 'Bug', idea: 'Idea', other: 'Message' } as const;
const PLATFORM = { mac: 'Mac', android: 'Android', both: 'Mac and Android', website: 'Website' };

/** A report from the website's /report form, to the owner. Every field is the reporter's. */
export function feedbackReport(report: {
  kind: keyof typeof KIND;
  platform: keyof typeof PLATFORM;
  message: string;
  steps?: string;
  appVersion?: string;
  email?: string;
}): Email {
  const first = report.message.split('\n')[0]?.slice(0, 70) ?? '';
  return {
    subject: `[FuseOS ${KIND[report.kind].toLowerCase()}] ${first}`,
    ...render({
      preheader: `${KIND[report.kind]} on ${PLATFORM[report.platform]}`,
      heading: `${KIND[report.kind]} · ${PLATFORM[report.platform]}`,
      paragraphs: [
        report.message,
        ...(report.steps ? [`Steps: ${report.steps}`] : []),
        `App version: ${report.appVersion || 'not given'}`,
        report.email
          ? `From: ${report.email} — reply to this email to answer.`
          : 'No reply address given.',
      ],
      footerHtml: 'Sent from the Report a bug form on fuseos.theshaik.dev.',
      footerText: 'Sent from the Report a bug form on fuseos.theshaik.dev.',
    }),
  };
}
