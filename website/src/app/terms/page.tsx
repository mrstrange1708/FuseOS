import type { Metadata } from 'next';
import { PageShell, Prose } from '@/components/page-shell';
import { CONTACT, GITHUB } from '@/lib/site';

export const metadata: Metadata = {
  title: 'Terms of use · FuseOS',
  description: 'The terms for using the FuseOS apps, website and service.',
};

export default function TermsPage() {
  return (
    <PageShell eyebrow="Terms of use" title="The terms." intro="Last updated 30 September 2026.">
      <Prose>
        <p>
          These terms cover the FuseOS apps for macOS and Android, the website fuseos.theshaik.dev
          and the FuseOS service (together, “FuseOS”), made by Shaik Junaid Sami (“we”). By using
          FuseOS you agree to them.
        </p>

        <h2>A preview</h2>
        <p>
          FuseOS is early software, free to use. Features can change or stop working, and the
          service can be down at times. Keep your own copies of anything important — FuseOS moves
          things between your devices; it is not a backup.
        </p>

        <h2>Your account</h2>
        <ul>
          <li>You need to be at least 13, and give an email address that is yours.</li>
          <li>
            Keep your password safe. Every device signed in to your account can see what the others
            copy, send and receive, so only sign in on devices you control.
          </li>
          <li>You are responsible for what happens under your account.</li>
        </ul>

        <h2>Your content</h2>
        <p>
          What you copy and send stays yours. It travels between your own devices and never reaches
          our servers (see the <a href="/privacy">privacy policy</a>).
        </p>

        <h2>Acceptable use</h2>
        <p>Don&apos;t use FuseOS to:</p>
        <ul>
          <li>
            access devices or accounts that aren&apos;t yours, or monitor someone without consent;
          </li>
          <li>break the law, or send material you have no right to share;</li>
          <li>attack, overload or probe our servers, or get around their limits.</li>
        </ul>
        <p>We may suspend accounts that do.</p>

        <h2>The software</h2>
        <p>
          You may install and use the FuseOS apps for yourself. The source code is public on{' '}
          <a href={GITHUB}>GitHub</a> so you can see what it does, but it is not open source: all
          rights are reserved, and you may not redistribute or resell FuseOS or build a competing
          service from its code without our permission.
        </p>
        <p>
          The macOS app is not notarized by Apple and the Android app is installed from outside the
          Play Store. Download them only from fuseos.theshaik.dev or our GitHub releases.
        </p>

        <h2>No warranty</h2>
        <p>
          FuseOS is provided “as is”, without warranties of any kind. To the fullest extent the law
          allows, we are not liable for any indirect or consequential loss, or for lost data,
          arising from your use of FuseOS.
        </p>

        <h2>Ending</h2>
        <p>
          You can stop using FuseOS and ask us to delete your account at any time. We may end the
          service or these terms with notice by email where we can.
        </p>

        <h2>Changes</h2>
        <p>
          We may update these terms. The date above shows the latest version; for significant
          changes we email you first. Using FuseOS after a change means you accept it.
        </p>

        <h2>Contact</h2>
        <p>
          <a href={`mailto:${CONTACT}`}>{CONTACT}</a>
        </p>
      </Prose>
    </PageShell>
  );
}
