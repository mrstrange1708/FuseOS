import type { Metadata } from 'next';
import { PageShell, Prose } from '@/components/page-shell';
import { CONTACT } from '@/lib/site';

export const metadata: Metadata = {
  title: 'Help · FuseOS',
  description: 'Set up FuseOS, fix devices that will not link, and secure your account.',
};

const TOPICS = [
  { id: 'setup', label: 'Setting up' },
  { id: 'not-linking', label: "Devices won't link" },
  { id: 'mac', label: 'On the Mac' },
  { id: 'android', label: 'On Android' },
  { id: 'account', label: 'Your account' },
  { id: 'not-you', label: "A device that isn't yours" },
];

export default function HelpPage() {
  return (
    <PageShell
      eyebrow="Help"
      title="Setup, and fixes."
      intro="Most problems are one of a few things. Start with the one that matches."
    >
      <nav aria-label="Topics" className="mb-12 flex flex-wrap gap-2">
        {TOPICS.map((t) => (
          <a
            key={t.id}
            href={`#${t.id}`}
            className="rounded-full border border-white/10 px-4 py-2 text-sm text-muted transition-colors hover:border-ember/50 hover:text-ink"
          >
            {t.label}
          </a>
        ))}
      </nav>
      <Prose>
        <h2 id="setup">Setting up</h2>
        <ol>
          <li>
            <a href="/download">Download</a> FuseOS on your Mac and on your Android phone.
          </li>
          <li>
            Sign in on both with the <b>same account</b> — email and password, or Continue with
            Google.
          </li>
          <li>
            Put both on the <b>same Wi-Fi</b>. They find each other and link by themselves; there is
            no code to type.
          </li>
          <li>Copy something on one. It is on the other.</li>
        </ol>

        <h2 id="not-linking">Devices won&apos;t link</h2>
        <p>Check these, in order:</p>
        <ul>
          <li>
            <b>Same account, same Wi-Fi.</b> A phone on mobile data, or a Mac on another network,
            can&apos;t be reached — your data only travels over your own Wi-Fi.
          </li>
          <li>
            <b>Local network permission on the Mac.</b> System Settings → Privacy &amp; Security →
            Local Network → turn on FuseOS.
          </li>
          <li>
            <b>A network that keeps devices apart.</b> Campus, office, hotel and café Wi-Fi often
            block devices from talking to each other. Try your phone&apos;s hotspot with the Mac on
            it, or a home network.
          </li>
          <li>
            <b>The phone saving battery.</b> Some phones freeze apps when the screen is off. In
            FuseOS → You → Background activity, allow it.
          </li>
          <li>
            Press <b>Connect</b> on the Mac&apos;s Home. It looks for your phone right away.
          </li>
        </ul>

        <h2 id="mac">On the Mac</h2>
        <h3>“FuseOS can&apos;t be opened”</h3>
        <p>
          The preview isn&apos;t notarized by Apple yet. Open it once, then System Settings →
          Privacy &amp; Security → <b>Open Anyway</b>. You only do this once.
        </p>
        <h3>Trackpad, unlock and paste don&apos;t work</h3>
        <p>
          Those need <b>Accessibility</b>: System Settings → Privacy &amp; Security → Accessibility
          → turn on FuseOS.
        </p>

        <h2 id="android">On Android</h2>
        <h3>Installing the APK</h3>
        <p>
          Allow your browser to <b>install unknown apps</b> when Android asks. FuseOS isn&apos;t on
          the Play Store.
        </p>
        <h3>Sending what you copy</h3>
        <p>
          Android lets only the app on screen read the clipboard, so FuseOS shows a pop-up the
          moment you tap Copy — one tap sends it. You can also use the <b>Send clipboard</b> Quick
          Settings tile.
        </p>
        <h3>Notifications on the Mac</h3>
        <p>
          Turn on FuseOS in Settings → Notifications → <b>Notification access</b>, then Notification
          sync in FuseOS → You.
        </p>

        <h2 id="account">Your account</h2>
        <h3>Forgot your password</h3>
        <p>
          On the sign-in screen of either app, type your email and tap <b>Forgot password?</b>.
          We&apos;ll email a link. Resetting signs every device out, so sign in again after.
        </p>
        <h3>Didn&apos;t get an email</h3>
        <p>
          Check spam, and that you typed the address you signed up with. Emails come from
          noreply@fuseos.theshaik.dev.
        </p>

        <h2 id="not-you">A device that isn&apos;t yours</h2>
        <p>
          Every device on your account shares its clipboard, files and notifications with the
          others, so act at once:
        </p>
        <ol>
          <li>
            On a device you trust, sign out, then use <b>Forgot password?</b> to set a new password.
            That signs <b>every</b> device out.
          </li>
          <li>Sign in again, open Devices, and remove the one you don&apos;t recognise.</li>
          <li>
            Tell us at <a href={`mailto:${CONTACT}`}>{CONTACT}</a>.
          </li>
        </ol>

        <h2 id="contact">Still stuck?</h2>
        <p>
          <a href="/report">Report it here</a> or email <a href={`mailto:${CONTACT}`}>{CONTACT}</a>.
        </p>
      </Prose>
    </PageShell>
  );
}
