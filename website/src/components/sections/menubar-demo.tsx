'use client';

import { useEffect, useState } from 'react';
import { AnimatePresence, motion } from 'motion/react';
import {
  IconBattery3,
  IconBrandApple,
  IconCheck,
  IconCompass,
  IconDeviceLaptop,
  IconDeviceMobile,
  IconFileUpload,
  IconPlayerPauseFilled,
  IconPlayerTrackNextFilled,
  IconPower,
  IconAlignLeft,
  IconScreenShare,
  IconWifi,
  IconAppWindow,
} from '@tabler/icons-react';
import { FuseMark } from '@/components/fuse-mark';
import { MacWallpaper, Photo } from '@/components/devices';
import { cn } from '@/lib/utils';

const CLIPS = [
  { id: 1, text: '4471 — buzz twice, 3rd floor', from: 'From Pixel 8', ago: '2m' },
  { id: 2, text: 'https://maps.app.goo.gl/tx8Qe', from: 'Copied here', ago: '9m' },
  { id: 3, text: 'Screenshot 09:41', from: 'From Pixel 8', ago: '14m', image: true },
];

/** One crossing of the link: a counter so each plays once, and which way it went. */
type Shot = { n: number; toPhone: boolean };

/**
 * The FuseOS menu bar item, live: the same popover the Mac app opens, on a Mac desktop.
 * Click the mark to open or close it; click a clip and it really lands on your clipboard.
 */
export function MenuBarDemo() {
  const [open, setOpen] = useState(true);
  const [copied, setCopied] = useState<number | null>(null);
  const [shot, setShot] = useState<Shot>({ n: 0, toPhone: true });
  const fire = (toPhone: boolean) => setShot((s) => ({ n: s.n + 1, toPhone }));

  // Something crosses every few seconds, both ways — as it does on a real desk. Not for
  // people who asked for less motion.
  useEffect(() => {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    const id = setInterval(() => setShot((s) => ({ n: s.n + 1, toPhone: !s.toPhone })), 3200);
    return () => clearInterval(id);
  }, []);

  const copy = async (clip: (typeof CLIPS)[number]) => {
    try {
      await navigator.clipboard.writeText(clip.text);
    } catch {
      // Clipboard access can be refused (no focus, an old browser); the demo still reacts.
    }
    setCopied(clip.id);
    fire(true); // copied on the Mac → it syncs to the phone
    setTimeout(() => setCopied((c) => (c === clip.id ? null : c)), 1300);
  };

  return (
    <section id="menubar" className="relative overflow-hidden bg-void py-28">
      <div className="mx-auto grid max-w-6xl items-center gap-14 px-4 sm:px-6 lg:grid-cols-[1fr_1.15fr]">
        <div>
          <p className="font-mono text-xs tracking-[0.14em] text-ember uppercase">The menu bar</p>
          <h2 className="mt-4 font-display text-[clamp(36px,5vw,64px)] leading-[0.98] font-black tracking-[-0.04em]">
            Everything is one click from the menu bar.
          </h2>
          <p className="mt-6 max-w-[48ch] text-lg leading-relaxed text-muted">
            The link, live: a spark crosses every time something moves, in the direction it went.
            Your phone&apos;s battery, what it is playing, your last clips and any file on the way.
            Open the phone&apos;s link, mirror its screen, or send a file in one click.
          </p>
          <p className="mt-6 font-mono text-xs text-muted/80">
            Try it: click a clip, and it&apos;s on your clipboard.
          </p>
        </div>

        {/* A slice of a Mac desktop: wallpaper, menu bar, and the FuseOS item. */}
        <div className="relative overflow-hidden rounded-[28px] border border-white/10 shadow-[0_40px_100px_-40px_rgb(0_0_0/0.9)]">
          <MacWallpaper />
          <div className="relative z-10 flex h-8 items-center justify-between bg-black/35 px-4 text-[12px] text-white/85 backdrop-blur">
            <span className="flex items-center gap-4">
              <IconBrandApple size={14} />
              <b className="font-semibold">Notes</b>
              <span className="hidden text-white/60 sm:inline">File Edit Format View</span>
            </span>
            <span className="flex items-center gap-3">
              <button
                type="button"
                onClick={() => setOpen((o) => !o)}
                aria-expanded={open}
                aria-label="FuseOS menu"
                className={cn(
                  'grid h-6 w-9 place-items-center rounded-md transition-colors',
                  open ? 'bg-white/20' : 'hover:bg-white/10',
                )}
              >
                <FuseMark className="h-3 w-6 text-white" />
              </button>
              <IconWifi size={14} />
              <IconBattery3 size={16} />
              <span className="font-mono text-[11px]">Tue 9:41</span>
            </span>
          </div>

          <div className="relative h-[560px] sm:h-[600px]">
            <AnimatePresence>
              {open && (
                <motion.div
                  initial={{ opacity: 0, y: -8, scale: 0.97 }}
                  animate={{ opacity: 1, y: 0, scale: 1 }}
                  exit={{ opacity: 0, y: -6, scale: 0.98 }}
                  transition={{ type: 'spring', bounce: 0.18, duration: 0.45 }}
                  style={{ transformOrigin: 'top right' }}
                  className="absolute top-2 right-2 left-2 grid gap-2.5 rounded-2xl border border-white/10 bg-[#0c0e14]/92 p-3 shadow-2xl backdrop-blur-xl sm:left-auto sm:w-[340px]"
                >
                  <div className="flex items-center gap-2 px-0.5">
                    <FuseMark className="h-3.5 w-7 text-ink" />
                    <b className="font-mono text-[15px] text-ink">FuseOS</b>
                    <span className="rounded-full bg-ember/15 px-2 py-0.5 font-mono text-[10px] font-semibold text-ember">
                      Linked
                    </span>
                    <span className="ml-auto grid h-6 w-6 place-items-center rounded-md bg-white/5 text-muted">
                      <IconAppWindow size={14} />
                    </span>
                  </div>

                  <div className="rounded-xl border border-ember/30 bg-surface p-3 shadow-[0_0_40px_-18px_rgb(255_122_69/0.6)]">
                    <div className="flex items-center">
                      <span className="grid h-9 w-9 place-items-center rounded-full bg-ember/15 text-ember">
                        <IconDeviceLaptop size={18} />
                      </span>
                      <Filament shot={shot} />
                      <span className="grid h-9 w-9 place-items-center rounded-full bg-ember/15 text-ember">
                        <IconDeviceMobile size={18} />
                      </span>
                    </div>
                    <div className="mt-2.5 flex items-center gap-3">
                      <div className="min-w-0 flex-1">
                        <p className="hero-grad text-[15px] font-bold">Pixel 8</p>
                        <p className="font-mono text-[10.5px] text-muted">
                          Linked · direct · 38 ms
                        </p>
                      </div>
                      <BatteryRing percent={82} />
                    </div>
                  </div>

                  <div className="grid grid-cols-3 gap-2">
                    {[
                      { icon: IconCompass, label: 'Open link' },
                      { icon: IconScreenShare, label: 'Mirror' },
                      { icon: IconFileUpload, label: 'Send file' },
                    ].map(({ icon: Icon, label }) => (
                      <span
                        key={label}
                        className="grid place-items-center gap-1 rounded-xl border border-white/[0.07] bg-surface py-2.5 text-[11.5px] font-semibold text-ink"
                      >
                        <Icon size={16} className="text-ember" />
                        {label}
                      </span>
                    ))}
                  </div>

                  <div className="flex items-center gap-3 rounded-xl border border-white/[0.07] bg-surface p-2.5">
                    <Photo className="h-10 w-10 shrink-0 rounded-lg" />
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-[13px] font-semibold text-ink">Midnight City</p>
                      <p className="font-mono text-[10px] text-muted">M83</p>
                    </div>
                    <span className="grid h-8 w-8 place-items-center rounded-full bg-ember text-white">
                      <IconPlayerPauseFilled size={14} />
                    </span>
                    <IconPlayerTrackNextFilled size={16} className="mr-1 text-ink" />
                  </div>

                  <div className="rounded-xl border border-white/[0.07] bg-surface p-3">
                    <p className="flex items-center justify-between font-mono text-[9.5px] font-semibold tracking-[0.1em] text-muted uppercase">
                      Recent clips
                      <span className="rounded-full bg-surface-alt px-1.5 py-0.5 tracking-normal">
                        {CLIPS.length}
                      </span>
                    </p>
                    <ul className="mt-2 grid gap-0.5">
                      {CLIPS.map((clip) => (
                        <li key={clip.id}>
                          <button
                            type="button"
                            onClick={() => copy(clip)}
                            className="flex w-full items-center gap-2.5 rounded-lg px-1.5 py-1.5 text-left transition-colors hover:bg-surface-alt"
                          >
                            {clip.image ? (
                              <Photo className="h-[26px] w-[26px] shrink-0 rounded-md" />
                            ) : (
                              <span className="grid h-[26px] w-[26px] shrink-0 place-items-center rounded-md bg-ember/12 text-ember">
                                <IconAlignLeft size={12} />
                              </span>
                            )}
                            <span className="min-w-0 flex-1">
                              <span className="block truncate text-[12.5px] text-ink">
                                {clip.image ? 'Image' : clip.text}
                              </span>
                              <span className="block font-mono text-[9.5px] text-muted">
                                {clip.from}
                              </span>
                            </span>
                            <AnimatePresence mode="wait" initial={false}>
                              {copied === clip.id ? (
                                <motion.span
                                  key="c"
                                  initial={{ opacity: 0, scale: 0.8 }}
                                  animate={{ opacity: 1, scale: 1 }}
                                  exit={{ opacity: 0 }}
                                  className="flex items-center gap-1 text-[10.5px] font-semibold text-ember"
                                >
                                  <IconCheck size={12} /> Copied
                                </motion.span>
                              ) : (
                                <motion.span
                                  key="t"
                                  initial={{ opacity: 0 }}
                                  animate={{ opacity: 1 }}
                                  exit={{ opacity: 0 }}
                                  className="font-mono text-[9.5px] text-muted"
                                >
                                  {clip.ago}
                                </motion.span>
                              )}
                            </AnimatePresence>
                          </button>
                        </li>
                      ))}
                    </ul>
                  </div>

                  <div className="grid grid-cols-[1fr_auto] gap-2">
                    <span className="flex items-center justify-center gap-1.5 rounded-[9px] border border-white/10 bg-surface px-3 py-2 text-[12px] font-semibold text-ink">
                      <IconAppWindow size={14} /> Open FuseOS
                    </span>
                    <span className="grid place-items-center rounded-[9px] border border-white/10 bg-surface px-3 py-2 text-ink">
                      <IconPower size={14} />
                    </span>
                  </div>
                </motion.div>
              )}
            </AnimatePresence>
          </div>
        </div>
      </div>
    </section>
  );
}

function BatteryRing({ percent }: { percent: number }) {
  const r = 14;
  const c = 2 * Math.PI * r;
  return (
    <span
      className="relative grid h-[34px] w-[34px] place-items-center"
      title={`Phone battery ${percent}%`}
    >
      <svg viewBox="0 0 34 34" className="absolute inset-0 -rotate-90">
        <circle cx="17" cy="17" r={r} fill="none" stroke="#343b47" strokeWidth="3" />
        <circle
          cx="17"
          cy="17"
          r={r}
          fill="none"
          stroke="#FF7A45"
          strokeWidth="3"
          strokeLinecap="round"
          strokeDasharray={`${(c * percent) / 100} ${c}`}
        />
      </svg>
      <span className="font-mono text-[10px] font-semibold text-ink">{percent}</span>
    </span>
  );
}

/**
 * The line between the Mac (left) and the phone (right), as the apps draw it: a resting
 * dot, and for each crossing a comet with an amber tail that lands in a ring.
 */
function Filament({ shot }: { shot: Shot }) {
  const from = shot.toPhone ? '-10%' : '110%';
  const to = shot.toPhone ? '110%' : '-10%';
  return (
    <div className="relative mx-2 h-5 flex-1 overflow-visible">
      <div className="absolute inset-x-0 top-1/2 h-px -translate-y-1/2 bg-gradient-to-r from-ember/15 via-ember/55 to-ember/15" />
      <span className="absolute top-1/2 left-1/2 h-1.5 w-1.5 -translate-x-1/2 -translate-y-1/2 rounded-full bg-ember/80" />
      <AnimatePresence>
        {shot.n > 0 && (
          <motion.span
            key={shot.n}
            className={cn(
              'absolute top-1/2 h-[3px] w-12 -translate-y-1/2 rounded-full shadow-[0_0_14px_#ffb347]',
              shot.toPhone
                ? 'bg-gradient-to-r from-transparent to-amber'
                : 'bg-gradient-to-l from-transparent to-amber',
            )}
            initial={{ left: from, opacity: 0 }}
            animate={{ left: to, opacity: [0, 1, 1, 0] }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.7, ease: 'easeInOut' }}
            style={{ translateX: '-50%' }}
          />
        )}
      </AnimatePresence>
    </div>
  );
}
