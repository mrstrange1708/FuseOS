'use client';

import { useRef, type ReactNode } from 'react';
import {
  IconBatteryCharging,
  IconBell,
  IconBrandWhatsapp,
  IconCopy,
  IconDeviceDesktop,
  IconExternalLink,
  IconGauge,
  IconKey,
  IconHandFinger,
  IconLayoutDashboard,
  IconLock,
  IconMusic,
  IconPhone,
  IconPhoneCall,
  IconPhoneOff,
  IconRoute,
  IconScreenShare,
  IconBellRinging,
} from '@tabler/icons-react';
import { GlowingEffect } from '@/components/ui/glowing-effect';
import { cn } from '@/lib/utils';
import { gsap, useGSAP } from '@/lib/gsap';

type Tile = {
  Icon: typeof IconBell;
  title: string;
  body: string;
  className: string;
  art: ReactNode;
};

/** The Mac's Dynamic Island, as FuseOS draws it under the notch. */
function Island({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <div
      className={cn(
        'mx-auto flex w-full max-w-[340px] items-center gap-3 rounded-[22px] bg-black px-3.5 py-3 shadow-[0_18px_50px_-20px_rgb(255_122_69/0.55)] ring-1 ring-white/10',
        className,
      )}
    >
      {children}
    </div>
  );
}

const TILES: Tile[] = [
  {
    Icon: IconBell,
    title: 'Notifications, and replies',
    body: "Your phone's notifications land in the island on your Mac. Reply to a message right there, without picking the phone up.",
    className: 'md:col-span-3 md:row-span-2',
    art: (
      <div className="mt-8 grid gap-3">
        <Island className="scale-[0.94] opacity-60">
          <span className="grid h-9 w-9 shrink-0 place-items-center rounded-xl bg-[#1f6feb] text-[13px] font-bold text-white">
            ₹
          </span>
          <div className="min-w-0 flex-1">
            <p className="text-[13px] font-semibold text-white">Payment received</p>
            <p className="truncate text-[12px] text-white/60">₹2,400 credited to your account</p>
          </div>
          <span className="font-mono text-[10px] text-white/40">2m</span>
        </Island>
        <Island>
          <span className="grid h-9 w-9 shrink-0 place-items-center rounded-xl bg-[#25d366] text-white">
            <IconBrandWhatsapp size={20} />
          </span>
          <div className="min-w-0 flex-1">
            <p className="text-[13px] font-semibold text-white">Ananya</p>
            <p className="truncate text-[12px] text-white/60">Are we still on for 7?</p>
          </div>
          <span className="font-mono text-[10px] text-white/40">now</span>
        </Island>
        <Island className="py-2.5">
          <span className="min-w-0 flex-1 font-mono text-[12px] text-white">
            <span className="cx-type inline-block overflow-hidden align-bottom whitespace-nowrap">
              On my way, 5 min
            </span>
            <span className="cx-caret ml-px inline-block h-3.5 w-px translate-y-0.5 bg-ember" />
          </span>
          <span className="rounded-full bg-ember px-3 py-1 text-[11px] font-semibold text-white">
            Send
          </span>
        </Island>
      </div>
    ),
  },
  {
    Icon: IconPhoneCall,
    title: 'Answer calls on your Mac',
    body: 'A call rings in the island with Answer and Decline. Pick up from the Mac and talk on the phone.',
    className: 'md:col-span-3',
    art: (
      <div className="mt-6">
        <Island>
          <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-white/10 text-white">
            <IconPhone size={18} />
          </span>
          <div className="min-w-0 flex-1">
            <p className="text-[13px] font-semibold text-white">Mom</p>
            <p className="text-[12px] text-white/60">Mobile · ringing</p>
          </div>
          <span className="grid h-8 w-8 place-items-center rounded-full bg-[#ff453a] text-white">
            <IconPhoneOff size={15} />
          </span>
          <span className="relative grid h-8 w-8 place-items-center rounded-full bg-[#30d158] text-white">
            <span className="cx-ring absolute inset-0 rounded-full bg-[#30d158]" />
            <IconPhone size={15} className="relative" />
          </span>
        </Island>
      </div>
    ),
  },
  {
    Icon: IconLock,
    title: 'Walk away, it locks',
    body: 'Your Mac reads how far your phone is over Bluetooth. Take the phone to another room and the Mac locks. Unlock the phone beside it and the Mac unlocks too.',
    className: 'md:col-span-3',
    art: (
      <div className="relative mt-6 flex h-20 items-center justify-center">
        {[0, 1, 2].map((i) => (
          <span
            key={i}
            className="cx-radar absolute h-16 w-16 rounded-full border border-ember/60"
            style={{ animationDelay: `${i * 0.8}s` }}
          />
        ))}
        <span className="relative grid h-11 w-11 place-items-center rounded-full bg-ember/20 text-ember ring-1 ring-ember/40">
          <IconLock size={20} />
        </span>
      </div>
    ),
  },
  {
    Icon: IconScreenShare,
    title: 'Your phone, in a window',
    body: "Mirror the phone's screen on the Mac, then click, scroll and type into it with the Mac's own keyboard and trackpad.",
    className: 'md:col-span-2 md:row-span-2',
    art: (
      <div className="relative mx-auto mt-8 h-56 w-[118px] rounded-[22px] border-[5px] border-[#23262f] bg-gradient-to-b from-[#1b1f2a] to-[#0e1017] p-3">
        <div className="grid grid-cols-3 gap-2.5">
          {Array.from({ length: 12 }, (_, i) => (
            <span
              key={i}
              className="aspect-square rounded-[7px]"
              style={{ background: `hsl(${(i * 37) % 360} 55% ${i % 3 ? 55 : 45}% / 0.55)` }}
            />
          ))}
        </div>
        <span className="cx-tap absolute h-7 w-7 rounded-full border-2 border-amber bg-amber/25" />
      </div>
    ),
  },
  {
    Icon: IconHandFinger,
    title: 'A trackpad in your pocket',
    body: 'Use the phone as a trackpad and keyboard for the Mac. Three fingers across switch desktops, up opens Mission Control.',
    className: 'md:col-span-2',
    art: (
      <div className="relative mt-6 h-14 overflow-hidden rounded-xl border border-white/[0.07] bg-white/[0.03]">
        <div className="cx-swipe absolute top-1/2 left-1/2 flex -translate-y-1/2 gap-2">
          {[0, 1, 2].map((i) => (
            <span key={i} className="h-4 w-4 rounded-full bg-amber/80 shadow-[0_0_12px_#ffb347]" />
          ))}
        </div>
      </div>
    ),
  },
  {
    Icon: IconDeviceDesktop,
    title: 'A second display',
    body: 'Turn the phone into an extra screen for the Mac. Drag a window across and it lands on the phone.',
    className: 'md:col-span-2',
    art: (
      <div className="mt-6 flex items-center justify-center gap-3">
        <span className="relative h-14 w-24 rounded-md border border-white/15 bg-white/[0.03]">
          <span className="cx-drag absolute top-3 h-6 w-9 rounded bg-gradient-to-br from-ember to-amber" />
        </span>
        <span className="h-14 w-8 rounded-md border border-white/15 bg-white/[0.03]" />
      </div>
    ),
  },
  {
    Icon: IconMusic,
    title: 'Now Playing',
    body: 'See what the phone is playing on the Mac and control it: play, pause, skip, scrub.',
    className: 'md:col-span-4',
    art: (
      <div className="mt-6 flex items-end gap-1.5 px-1">
        {[0.5, 0.9, 0.35, 0.75, 0.6, 1, 0.45, 0.8].map((h, i) => (
          <span
            key={i}
            className="cx-eq w-2 origin-bottom rounded-full bg-gradient-to-t from-ember to-amber"
            style={{ height: `${h * 44}px`, animationDelay: `${i * 0.11}s` }}
          />
        ))}
        <span className="ml-3 self-center">
          <span className="block text-[13px] text-ink">Midnight City</span>
          <span className="block font-mono text-[10.5px] text-muted">M83 · Spotify</span>
        </span>
      </div>
    ),
  },
  {
    Icon: IconCopy,
    title: 'Copy anywhere, keep Gboard',
    body: 'Copy in any Android app and a pop-up asks if it should go to the Mac. One tap. No special keyboard to switch to.',
    className: 'md:col-span-3',
    art: (
      <div className="mt-6">
        <div className="mx-auto flex max-w-[260px] items-center gap-2.5 rounded-full bg-black px-3 py-2 ring-1 ring-white/10">
          <IconCopy size={15} className="text-ember" />
          <span className="flex-1 truncate text-[12px] text-white">Copied · 4471 buzz twice</span>
          <span className="rounded-full bg-ember px-2.5 py-0.5 text-[10.5px] font-semibold text-white">
            Send
          </span>
        </div>
      </div>
    ),
  },
  {
    Icon: IconKey,
    title: 'Codes, pasted for you',
    body: 'A sign-in or payment code texted or emailed to your phone shows in the island. Copy it, or Paste it straight into the box you are typing in. It never leaves your Mac.',
    className: 'md:col-span-3',
    art: (
      <div className="mt-6">
        <Island>
          <span className="grid h-9 w-9 shrink-0 place-items-center rounded-xl bg-white/10 text-white">
            <IconKey size={18} />
          </span>
          <div className="min-w-0 flex-1">
            <p className="text-[13px] font-semibold text-white">Messages</p>
            <p className="truncate text-[12px] text-white/60">482913 is your verification code</p>
          </div>
          <span className="rounded-full bg-ember px-2.5 py-1 font-mono text-[10.5px] font-semibold text-white">
            Copy 482913
          </span>
          <span className="rounded-full bg-ember px-2.5 py-1 text-[10.5px] font-semibold text-white">
            Paste
          </span>
        </Island>
      </div>
    ),
  },
];

/** The smaller pieces, together: each one is a line, not a tile. */
const EXTRAS = [
  { Icon: IconBellRinging, text: 'Ring your phone from the Mac' },
  { Icon: IconExternalLink, text: 'Open a link on the other device' },
  { Icon: IconRoute, text: 'Live activities: rides, deliveries, timers' },
  { Icon: IconBatteryCharging, text: 'Battery and charging, both ways' },
  { Icon: IconLayoutDashboard, text: 'A home-screen widget on the phone' },
  { Icon: IconGauge, text: 'Live sync speed, measured on both apps' },
];

function Card({ t }: { t: Tile }) {
  return (
    <li className={cn('continuity-card list-none', t.className)}>
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
            <t.Icon size={22} stroke={1.7} />
          </span>
          <h3 className="mt-5 font-display text-2xl font-extrabold tracking-[-0.02em]">
            {t.title}
          </h3>
          <p className="mt-2 max-w-[46ch] leading-relaxed text-muted">{t.body}</p>
          <div className="mt-auto">{t.art}</div>
        </div>
      </div>
    </li>
  );
}

/**
 * Everything beyond the clipboard: the continuity features, each with a small live
 * picture of what it looks like. Motion is CSS (`cx-*` in globals.css) and stops for
 * people who ask for reduced motion.
 */
export function Continuity() {
  const root = useRef<HTMLElement>(null);
  useGSAP(
    () => {
      gsap.matchMedia().add('(prefers-reduced-motion: no-preference)', () => {
        gsap.from('.continuity-card', {
          y: 60,
          opacity: 0,
          duration: 1,
          ease: 'expo.out',
          stagger: 0.06,
          scrollTrigger: { trigger: root.current, start: 'top 75%' },
        });
      });
    },
    { scope: root },
  );

  return (
    <section id="continuity" ref={root} className="relative overflow-hidden bg-void py-28">
      <div className="pointer-events-none absolute top-0 left-1/2 h-[520px] w-[900px] -translate-x-1/2 rounded-full bg-ember/10 blur-[140px]" />
      <div className="relative mx-auto max-w-6xl px-4 sm:px-6">
        <p className="font-mono text-xs uppercase tracking-[0.14em] text-ember">Continuity</p>
        <h2 className="mt-4 max-w-[20ch] font-display text-[clamp(36px,5.4vw,68px)] leading-[0.98] font-black tracking-[-0.04em]">
          Your phone, <span className="hero-grad">inside</span> your Mac.
        </h2>
        <p className="mt-5 max-w-[58ch] text-lg text-muted">
          The things an iPhone does with a Mac, for an Android phone: messages, calls, the screen,
          the music, and a Mac that locks when you walk away.
        </p>
        <ul className="mt-14 grid grid-cols-1 gap-4 md:auto-rows-[minmax(13rem,auto)] md:grid-cols-6">
          {TILES.map((t) => (
            <Card key={t.title} t={t} />
          ))}
        </ul>
        <ul className="mt-4 grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {EXTRAS.map(({ Icon, text }) => (
            <li
              key={text}
              className="continuity-card flex items-center gap-3 rounded-2xl border border-white/[0.07] bg-[#0e1017] px-4 py-3.5 text-[14px] text-ink"
            >
              <Icon size={18} className="shrink-0 text-ember" />
              {text}
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
