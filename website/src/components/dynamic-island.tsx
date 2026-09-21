'use client';

import { useEffect, useState } from 'react';
import { AnimatePresence, motion, useReducedMotion } from 'motion/react';
import {
  IconArrowRight,
  IconBell,
  IconClipboardCheck,
  IconDeviceLaptop,
  IconDeviceMobile,
  IconFileDownload,
  IconLink,
  IconPhoto,
} from '@tabler/icons-react';
import { FuseMark } from '@/components/fuse-mark';
import { pushIsland, useIsland, type IslandEvent } from '@/lib/island';

const KIND_ICON = {
  clip: IconClipboardCheck,
  image: IconPhoto,
  file: IconFileDownload,
  link: IconLink,
  notification: IconBell,
} as const;

/** One spring for every size change, so the pill always moves like one object. */
const SPRING = { type: 'spring', bounce: 0.32, duration: 0.62 } as const;

/**
 * The FuseOS Dynamic Island: a black pill pinned to the top of the page that swells to
 * show what just crossed between the devices — a copy, a photo, a file with its progress.
 *
 * It reads from `lib/island.ts`, so anything can drive it: the page's own demo, the
 * visitor copying text here, and later a real event source.
 */
export function DynamicIsland() {
  const event = useIsland();
  const [hovered, setHovered] = useState(false);
  const reduce = useReducedMotion();

  // Copy anything on this page and the island reacts, the way the Mac app does.
  useEffect(() => {
    const onCopy = () => {
      const text = window.getSelection()?.toString().trim();
      if (!text) return;
      pushIsland({ kind: 'clip', title: 'Copied — sent to Pixel 8', detail: text, from: 'mac' });
    };
    document.addEventListener('copy', onCopy);
    return () => document.removeEventListener('copy', onCopy);
  }, []);

  const mode = event ? 'event' : hovered ? 'peek' : 'idle';
  const size = {
    idle: { width: 132, height: 38, borderRadius: 22 },
    peek: { width: 268, height: 38, borderRadius: 22 },
    event: {
      width: event?.progress !== undefined ? 400 : 380,
      height: event?.progress !== undefined ? 92 : 78,
      borderRadius: 30,
    },
  }[mode];

  return (
    <div className="pointer-events-none fixed inset-x-0 top-3 z-50 flex justify-center px-4">
      <motion.div
        role="status"
        aria-live="polite"
        onHoverStart={() => setHovered(true)}
        onHoverEnd={() => setHovered(false)}
        initial={false}
        animate={size}
        transition={reduce ? { duration: 0 } : SPRING}
        style={{ maxWidth: 'calc(100vw - 32px)' }}
        className="pointer-events-auto relative overflow-hidden bg-black shadow-[0_10px_40px_-10px_rgb(0_0_0/0.9),0_0_0_1px_rgb(255_255_255/0.07)]"
      >
        <AnimatePresence mode="popLayout" initial={false}>
          {mode === 'event' && event ? (
            <EventBody key={event.id} event={event} />
          ) : (
            <motion.div
              key={mode}
              initial={{ opacity: 0, filter: 'blur(6px)' }}
              animate={{ opacity: 1, filter: 'blur(0px)' }}
              exit={{ opacity: 0, filter: 'blur(6px)' }}
              transition={{ duration: 0.25 }}
              className="absolute inset-0 flex items-center justify-between px-3.5"
            >
              <FuseMark className="h-3.5 w-7 text-white" />
              {mode === 'peek' ? (
                <span className="flex items-center gap-2 font-mono text-[11px] text-white/80">
                  <IconDeviceMobile size={13} /> Pixel 8<span className="text-ember">⇄</span>
                  <IconDeviceLaptop size={13} /> MacBook Air
                </span>
              ) : (
                <span className="relative flex h-2 w-2">
                  <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-ember opacity-60" />
                  <span className="relative inline-flex h-2 w-2 rounded-full bg-ember" />
                </span>
              )}
            </motion.div>
          )}
        </AnimatePresence>
      </motion.div>
    </div>
  );
}

function EventBody({ event }: { event: IslandEvent }) {
  const Icon = KIND_ICON[event.kind];
  const From = event.from === 'phone' ? IconDeviceMobile : IconDeviceLaptop;
  const To = event.from === 'phone' ? IconDeviceLaptop : IconDeviceMobile;
  const inFlight = event.progress !== undefined;

  return (
    <motion.div
      initial={{ opacity: 0, filter: 'blur(8px)', scale: 0.96 }}
      animate={{ opacity: 1, filter: 'blur(0px)', scale: 1 }}
      exit={{ opacity: 0, filter: 'blur(8px)', scale: 0.96 }}
      transition={{ duration: 0.3, delay: 0.08 }}
      className="absolute inset-0 flex flex-col justify-center gap-2.5 px-4"
    >
      <div className="flex items-center gap-3">
        <span className="grid h-11 w-11 shrink-0 place-items-center rounded-[14px] bg-gradient-to-br from-ember to-ember-deep text-white shadow-[0_0_24px_-4px_rgb(255_122_69/0.7)]">
          <Icon size={22} stroke={1.8} />
        </span>
        <div className="min-w-0 flex-1">
          <p className="font-mono text-[10.5px] uppercase tracking-[0.08em] text-white/50">
            {event.title}
          </p>
          <p className="truncate text-[14.5px] font-medium text-white">{event.detail}</p>
        </div>
        <span className="flex shrink-0 items-center gap-1 text-white/60">
          <From size={16} />
          <IconArrowRight size={13} className="text-ember" />
          <To size={16} />
        </span>
      </div>
      {inFlight && (
        <div className="h-1 w-full overflow-hidden rounded-full bg-white/10">
          <motion.div
            className="h-full rounded-full bg-gradient-to-r from-ember-deep to-amber"
            animate={{ width: `${Math.round((event.progress ?? 0) * 100)}%` }}
            transition={{ ease: 'easeOut', duration: 0.3 }}
          />
        </div>
      )}
    </motion.div>
  );
}
