'use client';

import { useRef } from 'react';
import { IconBrandApple, IconBrandAndroid } from '@tabler/icons-react';
import { Spotlight } from '@/components/ui/spotlight-new';
import { BackgroundBeams } from '@/components/ui/background-beams';
import { AndroidAppScreen, PixelPhone } from '@/components/devices';
import { gsap, SplitText, useGSAP } from '@/lib/gsap';

const EMBER_LIGHT = {
  gradientFirst:
    'radial-gradient(68.54% 68.72% at 55.02% 31.46%, hsla(18, 100%, 70%, .10) 0, hsla(18, 100%, 55%, .03) 50%, hsla(18, 100%, 45%, 0) 80%)',
  gradientSecond:
    'radial-gradient(50% 50% at 50% 50%, hsla(28, 100%, 75%, .07) 0, hsla(28, 100%, 55%, .02) 80%, transparent 100%)',
  gradientThird:
    'radial-gradient(50% 50% at 50% 50%, hsla(18, 100%, 75%, .05) 0, hsla(18, 100%, 45%, .02) 80%, transparent 100%)',
};

export function Hero() {
  const root = useRef<HTMLElement>(null);

  useGSAP(
    () => {
      const mm = gsap.matchMedia();
      mm.add('(prefers-reduced-motion: no-preference)', () => {
        const split = SplitText.create('.hero-title', { type: 'words,chars', mask: 'words' });
        const tl = gsap.timeline({ defaults: { ease: 'expo.out' } });
        tl.from(split.chars, { yPercent: 110, duration: 1.1, stagger: 0.018 })
          .from('.hero-fade', { y: 24, opacity: 0, duration: 0.9, stagger: 0.08 }, '-=0.8')
          .from('.hero-phone', { y: 120, rotate: 8, opacity: 0, duration: 1.4 }, '-=1.1');
        gsap.to('.hero-phone', {
          y: -14,
          rotate: -4,
          duration: 3.2,
          ease: 'sine.inOut',
          yoyo: true,
          repeat: -1,
          delay: 1.4,
        });
        return () => split.revert();
      });
    },
    { scope: root },
  );

  return (
    <section
      id="top"
      ref={root}
      className="relative isolate overflow-hidden bg-void pt-36 pb-24 md:pt-44"
    >
      <Spotlight {...EMBER_LIGHT} />
      <BackgroundBeams className="opacity-60" />
      <div className="pointer-events-none absolute inset-x-0 bottom-0 h-40 bg-gradient-to-t from-void to-transparent" />

      <div className="relative mx-auto grid max-w-6xl items-center gap-16 px-4 sm:px-6 lg:grid-cols-[1.6fr_1fr]">
        <div>
          <p className="hero-fade inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/[0.03] px-3 py-1.5 font-mono text-[11px] uppercase tracking-[0.12em] text-muted">
            <span className="h-1.5 w-1.5 rounded-full bg-ember" /> Android ⇄ macOS · Preview
          </p>
          <h1 className="hero-title mt-6 font-display text-[clamp(48px,7vw,98px)] leading-[0.92] font-black tracking-[-0.045em] text-ink">
            Copy on your phone. <span className="hero-grad">Paste</span> on your Mac.
          </h1>
          <p className="hero-fade mt-7 max-w-[52ch] text-lg leading-relaxed text-muted md:text-xl">
            FuseOS makes an Android phone and a Mac work like one device. Your clipboard, your files
            and the share sheet go both ways, straight across your Wi-Fi. Nothing you copy goes
            through a server.
          </p>
          <div className="hero-fade mt-9 flex flex-wrap gap-3">
            <a
              href="#download"
              className="group inline-flex items-center gap-2.5 rounded-2xl bg-gradient-to-b from-ember to-ember-deep px-6 py-4 font-semibold text-white shadow-[0_10px_40px_-10px_rgb(255_122_69/0.8),inset_0_1px_0_rgb(255_255_255/0.25)] transition-transform hover:-translate-y-0.5"
            >
              <IconBrandApple size={19} /> <IconBrandAndroid size={19} /> Download the preview
            </a>
            <a
              href="#story"
              className="inline-flex items-center gap-2 rounded-2xl border border-white/10 bg-white/[0.03] px-6 py-4 font-semibold text-ink backdrop-blur transition-colors hover:border-white/30"
            >
              See it move
            </a>
          </div>
          <p className="hero-fade mt-6 font-mono text-xs text-muted/80">
            Scroll to meet the island in the notch ↓
          </p>
        </div>

        <div className="relative flex justify-center">
          <div className="absolute top-1/2 left-1/2 h-72 w-72 -translate-x-1/2 -translate-y-1/2 rounded-full bg-ember/25 blur-[100px]" />
          <PixelPhone className="hero-phone relative -rotate-6">
            <AndroidAppScreen />
          </PixelPhone>
        </div>
      </div>
    </section>
  );
}
