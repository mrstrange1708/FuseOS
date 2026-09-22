'use client';

import { useState } from 'react';
import { AnimatePresence, motion } from 'motion/react';
import {
  IconArrowUpRight,
  IconBattery3,
  IconBell,
  IconBrandApple,
  IconCheck,
  IconDeviceMobile,
  IconFileUpload,
  IconPower,
  IconAlignLeft,
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
  { id: 4, text: 'ssh deploy@10.0.4.12', from: 'Copied here', ago: '1h' },
];

/**
 * The FuseOS menu bar item, live: the same popover the Mac app opens, on a Mac desktop.
 * Click the mark to open or close it; click a clip and it really lands on your clipboard.
 */
export function MenuBarDemo() {
  const [open, setOpen] = useState(true);
  const [copied, setCopied] = useState<number | null>(null);

  const copy = async (clip: (typeof CLIPS)[number]) => {
    try {
      await navigator.clipboard.writeText(clip.text);
    } catch {
      // Clipboard access can be refused (no focus, an old browser); the demo still reacts.
    }
    setCopied(clip.id);
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
            It shows which phone is linked and its battery, your last clips, and any files on the
            way. Click a clip to copy it back, or drop a file on the menu to send it. Your
            phone&apos;s notifications will show up here next.
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

                  <div className="flex items-center gap-3 rounded-xl border border-white/[0.07] bg-surface p-3">
                    <span className="grid h-10 w-10 place-items-center rounded-[10px] bg-ember/15 text-ember">
                      <IconDeviceMobile size={21} />
                    </span>
                    <div className="min-w-0 flex-1">
                      <p className="text-[14px] font-semibold text-ink">Pixel 8</p>
                      <p className="font-mono text-[10.5px] text-muted">connected · direct</p>
                    </div>
                    <BatteryRing percent={82} />
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

                  <div className="flex items-center gap-2.5 rounded-xl border border-white/[0.07] bg-surface p-3 opacity-75">
                    <IconBell size={15} className="text-muted" />
                    <p className="flex-1 text-[12px] text-muted">
                      Your phone&apos;s notifications will appear here.
                    </p>
                    <span className="rounded-full bg-surface-alt px-1.5 py-0.5 font-mono text-[9.5px] font-semibold text-muted">
                      SOON
                    </span>
                  </div>

                  <div className="grid grid-cols-[1fr_1fr_auto] gap-2">
                    <span className="flex items-center justify-center gap-1.5 rounded-[9px] bg-ember px-3 py-2 text-[12px] font-semibold text-white">
                      <IconFileUpload size={14} /> Send file…
                    </span>
                    <span className="flex items-center justify-center gap-1.5 rounded-[9px] border border-white/10 bg-surface px-3 py-2 text-[12px] font-semibold text-ink">
                      <IconArrowUpRight size={14} /> Open
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
