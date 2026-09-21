'use client';

import { useEffect, useState } from 'react';
import {
  AnimatePresence,
  motion,
  useReducedMotion,
  useScroll,
  useSpring,
  useTransform,
} from 'motion/react';
import {
  IconArrowRight,
  IconBell,
  IconBolt,
  IconBrandGithub,
  IconClipboardCheck,
  IconDeviceLaptop,
  IconDeviceMobile,
  IconDownload,
  IconFileDownload,
  IconHelp,
  IconLink,
  IconLock,
  IconPhoto,
  IconArrowsExchange,
} from '@tabler/icons-react';
import { FuseMark, Wordmark } from '@/components/fuse-mark';
import { pushIsland, useIsland, type IslandEvent } from '@/lib/island';
import { cn } from '@/lib/utils';

const KIND_ICON = {
  clip: IconClipboardCheck,
  image: IconPhoto,
  file: IconFileDownload,
  link: IconLink,
  notification: IconBell,
} as const;

/**
 * What the island says at rest, per section: it is a different island in every part of
 * the page. Keyed by section id; the order is the page's order.
 */
const SECTION_ISLANDS = [
  { id: 'top', Icon: IconArrowsExchange, label: 'Pixel 8 ⇄ MacBook Air' },
  { id: 'story', Icon: IconClipboardCheck, label: 'Live sync' },
  { id: 'mac', Icon: IconDeviceLaptop, label: 'On your Mac' },
  { id: 'features', Icon: IconBolt, label: 'One tap away' },
  { id: 'privacy', Icon: IconLock, label: 'AES-256-GCM' },
  { id: 'download', Icon: IconDownload, label: 'Preview · free' },
  { id: 'faq', Icon: IconHelp, label: 'Questions' },
] as const;

type SectionIsland = (typeof SECTION_ISLANDS)[number];

/** One spring for every size change, so the pill always moves like one object. */
const SPRING = { type: 'spring', bounce: 0.3, duration: 0.6 } as const;

/** The section whose top most recently crossed the upper third of the screen. */
function useCurrentSection(): SectionIsland {
  const [current, setCurrent] = useState<SectionIsland>(SECTION_ISLANDS[0]);
  useEffect(() => {
    const observer = new IntersectionObserver(
      (entries) => {
        const visible = entries.filter((e) => e.isIntersecting);
        if (!visible.length) return;
        const id = visible[visible.length - 1].target.id;
        const match = SECTION_ISLANDS.find((s) => s.id === id);
        if (match) setCurrent(match);
      },
      // A band a third of the way down: a section owns the island while it covers that line.
      { rootMargin: '-33% 0px -66% 0px' },
    );
    SECTION_ISLANDS.forEach((s) => {
      const el = document.getElementById(s.id);
      if (el) observer.observe(el);
    });
    return () => observer.disconnect();
  }, []);
  return current;
}

/**
 * The navigation bar: a glass pill across the top, with the Dynamic Island as its middle
 * segment. The island rides a track inside the bar from right to left as the page scrolls,
 * changes to fit the section you are in, and drops out of the bar to show an event — a
 * copy, a photo, a file with its progress.
 *
 * Events come from `lib/island.ts`, so anything can drive it: the page's own demo, the
 * visitor copying text here, and later a real event source.
 */
export function Navbar() {
  const event = useIsland();
  const section = useCurrentSection();
  const reduce = useReducedMotion();
  const [hovered, setHovered] = useState(false);
  const [scrolled, setScrolled] = useState(false);
  // A phone's bar has no room for a track: there the island sits centred, like the real one.
  const [wide, setWide] = useState(true);
  useEffect(() => {
    const query = window.matchMedia('(min-width: 640px)');
    const update = () => setWide(query.matches);
    update();
    query.addEventListener('change', update);
    return () => query.removeEventListener('change', update);
  }, []);

  // Scroll 0 → 1 carries the island from the track's right end to its left end. The
  // left/translate pair keeps it inside the track at any width: left: p%, x: -p%.
  const { scrollYProgress } = useScroll();
  const smooth = useSpring(scrollYProgress, { stiffness: 120, damping: 26, mass: 0.4 });
  const left = useTransform(smooth, (p) => `${(1 - p) * 100}%`);
  const x = useTransform(smooth, (p) => `${-(1 - p) * 100}%`);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 24);
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

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

  const inFlight = event?.progress !== undefined;

  return (
    <header className="fixed inset-x-0 top-3 z-50 px-3">
      <nav
        aria-label="Primary"
        className={cn(
          'relative mx-auto flex h-14 max-w-6xl items-center gap-3 rounded-full pr-2 pl-5',
          'border border-white/10 backdrop-blur-xl backdrop-saturate-150 transition-[background-color,box-shadow] duration-300',
          'shadow-[inset_0_1px_0_rgb(255_255_255/0.08),0_12px_40px_-16px_rgb(0_0_0/0.8)]',
          scrolled ? 'bg-[#0c0e14]/70' : 'bg-white/[0.03]',
        )}
      >
        <a href="#top" aria-label="FuseOS home" className="shrink-0">
          <span className="hidden sm:block">
            <Wordmark />
          </span>
          <FuseMark className="text-white sm:hidden" />
        </a>

        {/* The island's track: the bar's middle segment. */}
        <div className={cn('h-full min-w-0 flex-1', wide && 'relative')}>
          <motion.div
            style={!wide ? { left: '50%', x: '-50%' } : reduce ? { right: 0 } : { left, x }}
            className="absolute top-[7px]"
          >
            <motion.div
              layout
              role="status"
              aria-live="polite"
              onHoverStart={() => setHovered(true)}
              onHoverEnd={() => setHovered(false)}
              transition={reduce ? { duration: 0 } : SPRING}
              style={{ borderRadius: event ? 26 : 20 }}
              className={cn(
                'relative overflow-hidden bg-black shadow-[0_10px_30px_-10px_rgb(0_0_0/0.9),0_0_0_1px_rgb(255_255_255/0.08)]',
                event
                  ? cn('w-[min(380px,calc(100vw-40px))]', inFlight ? 'h-[92px]' : 'h-[76px]')
                  : 'h-10',
              )}
            >
              <AnimatePresence mode="popLayout" initial={false}>
                {event ? (
                  <EventBody key={`e${event.id}`} event={event} />
                ) : (
                  <motion.div
                    key={hovered ? 'peek' : section.id}
                    layout="position"
                    initial={{ opacity: 0, filter: 'blur(6px)', y: 6 }}
                    animate={{ opacity: 1, filter: 'blur(0px)', y: 0 }}
                    exit={{ opacity: 0, filter: 'blur(6px)', y: -6 }}
                    transition={{ duration: 0.25 }}
                    className="flex h-10 items-center gap-2.5 pr-4 pl-3 whitespace-nowrap"
                  >
                    <span className="relative flex h-2 w-2 shrink-0">
                      <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-ember opacity-60" />
                      <span className="relative inline-flex h-2 w-2 rounded-full bg-ember" />
                    </span>
                    {hovered ? (
                      <span className="flex items-center gap-1.5 font-mono text-[11px] text-white/80">
                        <IconDeviceMobile size={13} /> Pixel 8<span className="text-ember">⇄</span>
                        <IconDeviceLaptop size={13} /> MacBook Air
                      </span>
                    ) : (
                      <span className="flex items-center gap-1.5 font-mono text-[11px] text-white/85">
                        <section.Icon size={14} className="text-ember" />
                        {section.label}
                      </span>
                    )}
                  </motion.div>
                )}
              </AnimatePresence>
            </motion.div>
          </motion.div>
        </div>

        <div className="flex shrink-0 items-center gap-1 text-[14px] text-muted">
          <a
            className="hidden rounded-full px-3 py-2 transition-colors hover:bg-white/5 hover:text-ink lg:inline"
            href="#story"
          >
            How it feels
          </a>
          <a
            className="hidden rounded-full px-3 py-2 transition-colors hover:bg-white/5 hover:text-ink lg:inline"
            href="#privacy"
          >
            Privacy
          </a>
          <a
            className="hidden rounded-full p-2 transition-colors hover:bg-white/5 hover:text-ink sm:inline-flex"
            href="https://github.com/mrstrange1708/FuseOS"
            aria-label="Source on GitHub"
          >
            <IconBrandGithub size={19} />
          </a>
          <a
            className="rounded-full bg-gradient-to-b from-ember to-ember-deep px-4 py-2 font-semibold text-white shadow-[inset_0_1px_0_rgb(255_255_255/0.25)] transition-[filter] hover:brightness-110"
            href="#download"
          >
            Download
          </a>
        </div>
      </nav>
    </header>
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
      className="absolute inset-0 flex flex-col justify-center gap-2.5 px-3.5"
    >
      <div className="flex items-center gap-3">
        <span className="grid h-11 w-11 shrink-0 place-items-center rounded-[14px] bg-gradient-to-br from-ember to-ember-deep text-white shadow-[0_0_24px_-4px_rgb(255_122_69/0.7)]">
          <Icon size={22} stroke={1.8} />
        </span>
        <div className="min-w-0 flex-1">
          <p className="font-mono text-[10.5px] tracking-[0.08em] text-white/50 uppercase">
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
