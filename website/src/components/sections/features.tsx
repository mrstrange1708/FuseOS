'use client';

import type { ReactNode } from 'react';
import {
  IconBolt,
  IconClipboardCheck,
  IconDeviceMobileMessage,
  IconFileZip,
  IconLink,
  IconShare3,
} from '@tabler/icons-react';
import { GlowingEffect } from '@/components/ui/glowing-effect';
import { cn } from '@/lib/utils';
import { gsap, useGSAP } from '@/lib/gsap';
import { useRef } from 'react';

type Feature = {
  Icon: typeof IconBolt;
  title: string;
  body: string;
  spec: string;
  className: string;
  art?: ReactNode;
};

const FEATURES: Feature[] = [
  {
    Icon: IconClipboardCheck,
    title: 'One clipboard for both',
    body: 'Copy text or an image on either device and paste it on the other. Everything stays in a history on both devices, even after a restart.',
    spec: 'text · images · both directions',
    className: 'md:col-span-4 md:row-span-2',
    art: (
      <div className="mt-8 grid gap-2 font-mono text-[12px]">
        {[
          '4471 — buzz twice, 3rd floor',
          'https://maps.app.goo.gl/tx8Qe',
          'ssh deploy@10.0.4.12',
        ].map((c, i) => (
          <div
            key={c}
            className="flex items-center justify-between gap-3 rounded-xl border border-white/[0.06] bg-white/[0.03] px-3.5 py-2.5"
            style={{ opacity: 1 - i * 0.22 }}
          >
            <span className="truncate text-ink">{c}</span>
            <span className="shrink-0 text-ember">{i === 1 ? 'Mac → Pixel' : 'Pixel → Mac'}</span>
          </div>
        ))}
      </div>
    ),
  },
  {
    Icon: IconFileZip,
    title: 'Files, both ways',
    body: 'Drop a file on the Mac, or pick one on your phone. It arrives in Downloads, and you can watch it or cancel it partway.',
    spec: 'sha-256 verified · up to 1 GB',
    className: 'md:col-span-2 md:row-span-2',
    art: (
      <div className="mt-8 rounded-xl border border-white/[0.06] bg-white/[0.03] p-3.5">
        <p className="text-sm">trip-photos.zip</p>
        <p className="font-mono text-[11px] text-muted">Sending to Pixel 8 · 72%</p>
        <div className="mt-2.5 h-1.5 overflow-hidden rounded-full bg-white/10">
          <div className="feature-bar h-full w-[72%] rounded-full bg-gradient-to-r from-ember-deep to-amber" />
        </div>
      </div>
    ),
  },
  {
    Icon: IconShare3,
    title: 'From the share sheet',
    body: "Choose FuseOS in any app's Share menu to send a link, a photo or some text. The app doesn't need to be open.",
    spec: 'android today · mac next',
    className: 'md:col-span-2',
  },
  {
    Icon: IconLink,
    title: 'Links itself',
    body: 'Sign in to the same account on both devices and they find each other. There are no codes to scan.',
    spec: 'one account · automatic',
    className: 'md:col-span-2',
  },
  {
    Icon: IconDeviceMobileMessage,
    title: 'One tap from any app',
    body: 'Send your clipboard from Quick Settings, the notification, or the island. You never have to open FuseOS.',
    spec: 'tile · notification · island',
    className: 'md:col-span-2',
  },
];

function Card({ f }: { f: Feature }) {
  return (
    <li className={cn('feature-card list-none', f.className)}>
      <div className="relative h-full rounded-[1.6rem] border border-white/[0.07] p-2">
        <GlowingEffect
          spread={42}
          glow
          disabled={false}
          proximity={72}
          inactiveZone={0.01}
          borderWidth={2}
        />
        <div className="relative flex h-full flex-col overflow-hidden rounded-[1.2rem] bg-[#0e1017] p-6 shadow-[inset_0_1px_0_rgb(255_255_255/0.04)]">
          <span className="grid h-11 w-11 place-items-center rounded-xl border border-white/10 bg-white/[0.04] text-ember">
            <f.Icon size={22} stroke={1.7} />
          </span>
          <h3 className="mt-5 font-display text-2xl font-extrabold tracking-[-0.02em]">
            {f.title}
          </h3>
          <p className="mt-2 max-w-[46ch] leading-relaxed text-muted">{f.body}</p>
          {f.art}
          <p className="mt-auto pt-6 font-mono text-[11px] uppercase tracking-[0.1em] text-muted/70">
            {f.spec}
          </p>
        </div>
      </div>
    </li>
  );
}

export function Features() {
  const root = useRef<HTMLElement>(null);
  useGSAP(
    () => {
      gsap.matchMedia().add('(prefers-reduced-motion: no-preference)', () => {
        gsap.from('.feature-card', {
          y: 60,
          opacity: 0,
          duration: 1,
          ease: 'expo.out',
          stagger: 0.08,
          scrollTrigger: { trigger: root.current, start: 'top 75%' },
        });
      });
    },
    { scope: root },
  );

  return (
    <section id="features" ref={root} className="relative bg-void py-28">
      <div className="mx-auto max-w-6xl px-4 sm:px-6">
        <p className="font-mono text-xs uppercase tracking-[0.14em] text-ember">What it does</p>
        <h2 className="mt-4 max-w-[18ch] font-display text-[clamp(36px,5.4vw,68px)] leading-[0.98] font-black tracking-[-0.04em]">
          Handoff, for the phone Apple forgot.
        </h2>
        <p className="mt-5 max-w-[56ch] text-lg text-muted">
          Apple devices have always passed things to each other. An Android phone next to a Mac
          never could. FuseOS adds that link.
        </p>
        <ul className="mt-14 grid grid-cols-1 gap-4 md:auto-rows-[minmax(13rem,auto)] md:grid-cols-6">
          {FEATURES.map((f) => (
            <Card key={f.title} f={f} />
          ))}
        </ul>
      </div>
    </section>
  );
}
