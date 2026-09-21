import { Wordmark } from '@/components/fuse-mark';

const GITHUB = 'https://github.com/mrstrange1708/FuseOS';

const FAQ = [
  {
    q: 'Does my clipboard go to the cloud?',
    a: "No. Clips and files go straight from one device to the other over your Wi-Fi, encrypted with AES-256-GCM using keys that only your two devices hold. The server never receives them, so there's nothing of yours for it to store.",
  },
  {
    q: 'Why is sending from Android a tap and not automatic?',
    a: 'Since Android 10, only the app on screen can read the clipboard. FuseOS gets sending down to a single tap from Quick Settings, the notification, the island or the share sheet. Copying on the Mac needs no tap at all.',
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
    q: 'Is it open source?',
    a: 'Yes. The Android app, the Mac app and the server are all on GitHub.',
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

export function Footer() {
  return (
    <footer className="border-t border-white/[0.07] bg-void">
      <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-6 px-4 py-10 text-sm text-muted sm:px-6">
        <Wordmark />
        <span>Android ⇄ macOS continuity · clipboard, files, share sheet</span>
        <a className="hover:text-ink" href={GITHUB}>
          github.com/mrstrange1708/FuseOS
        </a>
      </div>
      <p
        aria-hidden="true"
        className="pointer-events-none -mb-[0.2em] select-none bg-gradient-to-b from-white/[0.07] to-transparent bg-clip-text text-center font-display text-[clamp(80px,22vw,320px)] leading-none font-black tracking-[-0.06em] text-transparent"
      >
        FuseOS
      </p>
    </footer>
  );
}
