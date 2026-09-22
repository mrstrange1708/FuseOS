import { IconBrandAndroid, IconBrandApple, IconDownload } from '@tabler/icons-react';
import { CardBody, CardContainer, CardItem } from '@/components/ui/3d-card';
import { AndroidAppScreen, PixelPhone } from '@/components/devices';

const RELEASE = 'https://github.com/mrstrange1708/FuseOS/releases/download/preview';

const PLATFORMS = [
  {
    name: 'macOS',
    Icon: IconBrandApple,
    file: 'FuseOS.dmg',
    meta: 'macOS 13 Ventura or later · Apple silicon',
    href: `${RELEASE}/FuseOS.dmg`,
    steps: [
      <>
        Open the DMG and drag <b>FuseOS</b> into <b>Applications</b>.
      </>,
      <>Open it once. macOS blocks it, because the preview isn&apos;t notarized by Apple yet.</>,
      <>
        Go to <b>System Settings → Privacy &amp; Security</b> and click <b>Open Anyway</b>. You only
        have to do this once.
      </>,
      <>
        When it asks to find devices on your local network, click <b>Allow</b>. That&apos;s how your
        phone reaches your Mac.
      </>,
    ],
  },
  {
    name: 'Android',
    Icon: IconBrandAndroid,
    file: 'FuseOS-preview.apk',
    meta: 'Android 8.0 or later',
    href: `${RELEASE}/FuseOS-preview.apk`,
    steps: [
      <>Download the APK on your phone and open it.</>,
      <>
        If Android asks, allow your browser to <b>install unknown apps</b>. FuseOS isn&apos;t on the
        Play Store yet.
      </>,
      <>
        Sign in, then allow <b>notifications</b>. They show when a file arrives, and they keep
        FuseOS connected in the background.
      </>,
      <>
        Add the <b>Send clipboard</b> tile to Quick Settings. Then sending your clipboard is one
        pull and one tap.
      </>,
    ],
  },
];

export function Download() {
  return (
    <section id="download" className="relative overflow-hidden bg-void py-28">
      <div className="relative mx-auto max-w-6xl px-4 sm:px-6">
        <p className="font-mono text-xs uppercase tracking-[0.14em] text-ember">Download</p>
        <h2 className="mt-4 font-display text-[clamp(40px,6vw,80px)] leading-[0.95] font-black tracking-[-0.045em]">
          Two apps. One device.
        </h2>
        <p className="mt-5 max-w-[52ch] text-lg text-muted">
          Both are free. Install one on each device and sign in with the same account. They&apos;ll
          find each other.
        </p>

        <div className="mt-14 grid gap-6 md:grid-cols-2">
          {PLATFORMS.map((p) => (
            <CardContainer key={p.name} containerClassName="py-0 block" className="w-full">
              <CardBody className="group/card relative h-auto w-full rounded-[1.75rem] border border-white/[0.08] bg-[#0e1017] p-8 [transform-style:preserve-3d]">
                <CardItem translateZ={40} className="flex w-full items-center justify-between">
                  <span className="flex items-center gap-3">
                    <p.Icon size={30} className="text-ink" />
                    <span className="font-display text-3xl font-black tracking-[-0.03em]">
                      {p.name}
                    </span>
                  </span>
                  <span className="rounded-full bg-ember/15 px-3 py-1 font-mono text-[11px] uppercase tracking-[0.08em] text-ember-ink">
                    Preview
                  </span>
                </CardItem>
                <CardItem translateZ={24} as="p" className="mt-3 font-mono text-[13px] text-muted">
                  {p.file} · {p.meta}
                </CardItem>
                <CardItem translateZ={60} className="mt-6 w-full">
                  <a
                    href={p.href}
                    className="flex w-full items-center justify-center gap-2.5 rounded-2xl bg-gradient-to-b from-ember to-ember-deep px-6 py-4 font-semibold text-white shadow-[0_14px_40px_-12px_rgb(255_122_69/0.8),inset_0_1px_0_rgb(255_255_255/0.25)] transition-[filter] hover:brightness-110"
                  >
                    <IconDownload size={19} /> Download for {p.name === 'macOS' ? 'Mac' : 'Android'}
                  </a>
                </CardItem>
                <CardItem translateZ={16} as="ol" className="mt-7 grid gap-3.5">
                  {p.steps.map((step, i) => (
                    <li
                      key={i}
                      className="grid grid-cols-[28px_1fr] gap-3 text-[15px] leading-relaxed text-muted [&_b]:font-semibold [&_b]:text-ink"
                    >
                      <span className="grid h-7 w-7 place-items-center rounded-full border border-white/15 font-mono text-xs text-ink">
                        {i + 1}
                      </span>
                      <span>{step}</span>
                    </li>
                  ))}
                </CardItem>
              </CardBody>
            </CardContainer>
          ))}
        </div>

        <p className="mt-10 rounded-2xl border border-dashed border-white/15 px-5 py-4 text-[15px] text-muted">
          <b className="text-ink">This is an early preview.</b> Both devices need to be on the same
          Wi-Fi. Found something broken?{' '}
          <a
            className="text-ember underline-offset-4 hover:underline"
            href="https://github.com/mrstrange1708/FuseOS/issues"
          >
            Open an issue
          </a>
          .
        </p>
      </div>

      {/* A last look at the phone, leaning into the footer. */}
      <div
        className="pointer-events-none relative mx-auto mt-24 hidden h-64 max-w-6xl overflow-hidden md:block"
        aria-hidden="true"
      >
        <div className="absolute left-1/2 top-0 -translate-x-1/2 rotate-[8deg]">
          <PixelPhone>
            <AndroidAppScreen />
          </PixelPhone>
        </div>
        <div className="absolute inset-x-0 bottom-0 h-40 bg-gradient-to-t from-void to-transparent" />
      </div>
    </section>
  );
}
