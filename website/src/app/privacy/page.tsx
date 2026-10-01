import type { Metadata } from 'next';
import { PageShell, Prose } from '@/components/page-shell';
import { CONTACT } from '@/lib/site';

export const metadata: Metadata = {
  title: 'Privacy policy · FuseOS',
  description:
    'What FuseOS keeps, what it never sees, and who helps run it. Your clipboard, files and notifications never reach our servers.',
};

export default function PrivacyPage() {
  return (
    <PageShell
      eyebrow="Privacy policy"
      title="What we keep. What we never see."
      intro="Last updated 30 September 2026."
    >
      <Prose>
        <p>
          FuseOS links your Android phone and your Mac. It is made by Shaik Junaid Sami (“we”). This
          policy covers the FuseOS apps for macOS and Android, the website fuseos.theshaik.dev, and
          the FuseOS server.
        </p>

        <h2>The short version</h2>
        <ul>
          <li>
            <b>
              What you copy, the files you send, your notifications, your screen and your calls
              never reach our servers.
            </b>{' '}
            They travel directly between your own devices over your Wi-Fi, encrypted (AES-256-GCM)
            with keys only your devices hold.
          </li>
          <li>
            Our server knows who you are (your account) and which devices are yours, so they can
            find each other. That is all it is for.
          </li>
          <li>We don&apos;t sell data, and we don&apos;t show ads.</li>
        </ul>

        <h2>What we store</h2>
        <h3>Your account</h3>
        <ul>
          <li>Your name and email address, and whether you have confirmed the email.</li>
          <li>
            Your password, stored only as a one-way hash — or, if you use Google, your Google
            account ID. We never see your Google password.
          </li>
          <li>
            Your signed-in sessions: when each was created and expires, the IP address and the app
            version it signed in from.
          </li>
        </ul>
        <h3>Your devices</h3>
        <ul>
          <li>
            Each device&apos;s name, whether it is a Mac or an Android phone, its public key (so
            your other devices can check it is really yours), its last battery level and when it was
            last online.
          </li>
          <li>
            While a device is connected, the server holds its address on your local network in
            memory, to introduce it to your other devices. That is never written to disk.
          </li>
        </ul>

        <h2>What never leaves your devices</h2>
        <p>
          Your clipboard (text and images), files, notifications and their replies, your
          phone&apos;s screen, calls, media controls and anything you type through FuseOS. These go
          straight from one of your devices to another over your Wi-Fi. We have no copy, and we
          couldn&apos;t read one: the keys stay on your devices. Clipboard history is kept on your
          devices only.
        </p>

        <h2>Usage statistics</h2>
        <p>
          The apps tell PostHog when they open and which features you use — “sent a copy”, “sent a
          file of 2 MB”, “started screen mirroring” — with your account ID, the app and its version,
          your device model and system version, and roughly where you are (city and country, which
          PostHog works out from your IP address). Never what you copied, a file&apos;s name or
          contents, a notification, or anything on your screen. It tells us how many people use
          FuseOS and which features matter, so we know what to fix first.
        </p>
        <p>
          To have your usage statistics deleted, email <a href={`mailto:${CONTACT}`}>{CONTACT}</a>.
        </p>

        <h2>Emails we send</h2>
        <ul>
          <li>Confirming your email, welcome, and password reset — when you ask for them.</li>
          <li>A notice whenever a new device signs in to your account, for your security.</li>
          <li>
            New release announcements. Every one has an unsubscribe link; unsubscribing stops them
            and nothing else.
          </li>
        </ul>

        <h2>Who helps us run FuseOS</h2>
        <p>These providers process data for us, only to provide the service:</p>
        <ul>
          <li>
            <b>Neon</b> — the database that holds your account and device list (Singapore).
          </li>
          <li>
            <b>Resend</b> — sends our emails, so it sees your name and email address.
          </li>
          <li>
            <b>Inngest</b> — runs background jobs, such as sending those emails. Jobs carry account
            and device IDs, not your email address.
          </li>
          <li>
            <b>Vercel</b> — hosts this website. <b>Cloudflare</b> — handles our domain&apos;s DNS.
          </li>
          <li>
            <b>Google</b> — only if you choose Continue with Google.
          </li>
          <li>
            <b>Sentry</b> (error reports) and <b>PostHog</b> (usage statistics, above): they receive
            technical details such as event names, app platform, sizes and timings — never anything
            you copy, send or receive. On this website, PostHog counts page views without cookies or
            stored identifiers, and without the part of the address after “?”.
          </li>
          <li>Our server host, which runs the FuseOS server.</li>
        </ul>

        <h2>How long we keep it</h2>
        <p>
          Your account and devices are kept while you have an account. Removing a device in FuseOS
          deletes its record. Sessions expire after 90 days without use. To delete your account and
          everything above, email <a href={`mailto:${CONTACT}`}>{CONTACT}</a> from the address you
          signed up with; we delete it within 30 days.
        </p>

        <h2>Your rights</h2>
        <p>
          You can ask for a copy of your data, to correct it, or to delete it — email{' '}
          <a href={`mailto:${CONTACT}`}>{CONTACT}</a>. You can also change your device names and
          remove devices in the apps yourself.
        </p>

        <h2>Children</h2>
        <p>FuseOS is not meant for children under 13, and we don&apos;t knowingly serve them.</p>

        <h2>Changes</h2>
        <p>
          If this policy changes, we update the date above, and for anything significant we email
          you first.
        </p>

        <h2>Contact</h2>
        <p>
          Questions about privacy: <a href={`mailto:${CONTACT}`}>{CONTACT}</a>.
        </p>
      </Prose>
    </PageShell>
  );
}
