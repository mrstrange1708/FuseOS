import { Wordmark } from '@/components/fuse-mark';
import { CONTACT, GITHUB } from '@/lib/site';

const FAQ = [
  {
    q: 'Does my clipboard go to the cloud?',
    a: "No. Clips and files go straight from one device to the other over your Wi-Fi, encrypted with AES-256-GCM using keys that only your two devices hold. The server never receives them, so there's nothing of yours for it to store.",
  },
  {
    q: 'Why is sending from Android a tap and not automatic?',
    a: 'Since Android 10, only the app on screen can read the clipboard. So FuseOS watches for the moment you tap Copy, and a pop-up offers to send it — one tap, and you keep Gboard. Copying on the Mac needs no tap at all.',
  },
  {
    q: 'Why does macOS warn me when I first open it?',
    a: "Apple only removes that warning for apps signed through its paid developer program. The preview isn't enrolled yet, so you confirm it once in Privacy & Security and it won't ask again.",
  },
  {
    q: 'Do my devices have to be on the same Wi-Fi?',
    a: "Yes, for now. That's what keeps it fast and keeps your data off the internet. Syncing between different networks is planned.",
  },
  {
    q: 'Can my Mac unlock my phone?',
    a: 'No — Android lets no app past its own lock screen, so unlocking the Mac only wakes the phone. The other way works: unlock the phone next to the Mac and the Mac unlocks. That part is experimental and opt-in: the Mac keeps your password in its Keychain and types it at the lock screen.',
  },
  {
    q: 'Can I read the code?',
    a: 'Yes. The Android app, the Mac app and the server are all public on GitHub, so you can check exactly what they do. The code is source-available, not open source: all rights are reserved.',
  },
];

export function Faq() {
  return (
    <section id="faq" className="bg-void py-24">
      <div className="mx-auto grid max-w-6xl gap-12 px-4 sm:px-6 lg:grid-cols-[1fr_1.6fr]">
        <div>
          <p className="font-mono text-xs uppercase tracking-[0.14em] text-ember">Questions</p>
          <h2 className="mt-4 font-display text-[clamp(34px,4.4vw,56px)] leading-[0.98] font-black tracking-[-0.04em]">
            Good to know.
          </h2>
        </div>
        <div className="divide-y divide-white/10 border-y border-white/10">
          {FAQ.map((f) => (
            <details key={f.q} className="group py-5">
              <summary className="flex cursor-pointer list-none items-center justify-between gap-6 text-lg font-semibold [&::-webkit-details-marker]:hidden">
                {f.q}
                <span className="font-mono text-2xl text-ember transition-transform group-open:rotate-45">
                  +
                </span>
              </summary>
              <p className="mt-3 max-w-[62ch] leading-relaxed text-muted">{f.a}</p>
            </details>
          ))}
        </div>
      </div>
    </section>
  );
}

const FOOTER = [
  {
    title: 'Product',
    links: [
      { href: '/download', label: 'Download' },
      { href: '/releases', label: 'All versions' },
      { href: '/#film', label: 'Watch the film' },
      { href: '/#continuity', label: 'Features' },
    ],
  },
  {
    title: 'Help',
    links: [
      { href: '/help', label: 'Help & setup' },
      { href: '/help#not-linking', label: "Devices won't link" },
      { href: '/report', label: 'Report a bug' },
    ],
  },
  {
    title: 'Legal',
    links: [
      { href: '/privacy', label: 'Privacy policy' },
      { href: '/terms', label: 'Terms of use' },
      { href: `mailto:${CONTACT}`, label: CONTACT },
    ],
  },
];

export function Footer() {
  return (
    <footer className="border-t border-white/[0.07] bg-void">
      <div className="mx-auto grid max-w-6xl gap-10 px-4 py-14 text-sm sm:px-6 md:grid-cols-[1.4fr_repeat(3,1fr)]">
        <div className="space-y-3">
          <Wordmark />
          <p className="max-w-[30ch] text-muted">
            Your Android phone and your Mac, as one. Straight over your Wi-Fi.
          </p>
          <a className="inline-block text-muted hover:text-ink" href={GITHUB}>
            github.com/mrstrange1708/FuseOS
          </a>
        </div>
        {FOOTER.map((column) => (
          <nav key={column.title} aria-label={column.title}>
            <p className="font-mono text-[11px] uppercase tracking-[0.14em] text-ember">
              {column.title}
            </p>
            <ul className="mt-4 space-y-2.5">
              {column.links.map((link) => (
                <li key={link.href}>
                  <a className="text-muted transition-colors hover:text-ink" href={link.href}>
                    {link.label}
                  </a>
                </li>
              ))}
            </ul>
          </nav>
        ))}
      </div>
      <p className="mx-auto max-w-6xl px-4 pb-6 text-xs text-muted/70 sm:px-6">
        © 2026 Shaik Junaid Sami. All rights reserved.
      </p>
      <p
        aria-hidden="true"
        className="pointer-events-none -mb-[0.2em] select-none bg-gradient-to-b from-white/[0.07] to-transparent bg-clip-text text-center font-display text-[clamp(80px,22vw,320px)] leading-none font-black tracking-[-0.06em] text-transparent"
      >
        FuseOS
      </p>
    </footer>
  );
}
