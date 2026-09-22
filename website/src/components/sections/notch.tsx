'use client';

import { useEffect, useRef, useState } from 'react';
import { AnimatePresence, motion, useReducedMotion } from 'motion/react';
import {
  IconBrandApple,
  IconClipboardCheck,
  IconDeviceLaptop,
  IconDeviceMobile,
  IconFileZip,
  IconLink,
  IconPhoto,
  IconWifi,
  IconBattery3,
} from '@tabler/icons-react';
import { FuseMark } from '@/components/fuse-mark';
import { Photo } from '@/components/devices';
import { gsap, ScrollTrigger, useGSAP } from '@/lib/gsap';
import { pushIsland, useIsland } from '@/lib/island';
import { cn } from '@/lib/utils';
import { scrollToY } from '@/lib/scroll';

/** The five things the island shows, in scroll order. */
const STEPS = [
  {
    Icon: IconClipboardCheck,
    label: 'Clipboard',
    title: 'Copy on your phone. It opens right here.',
    body: 'Text you copy on your Pixel appears in the notch and is already on your Mac’s clipboard. Press ⌘V.',
  },
  {
    Icon: IconPhoto,
    label: 'Images',
    title: 'Screenshots arrive as images.',
    body: 'Copy a photo or a screenshot and paste it straight into Keynote, Figma or a chat.',
  },
  {
    Icon: IconFileZip,
    label: 'Files',
    title: 'Files show their progress in the notch.',
    body: 'Every file is checked with SHA-256 when it arrives, then saved to Downloads. You can cancel one partway through.',
  },
  {
    Icon: IconLink,
    label: 'Share sheet',
    title: 'Send anything from the share sheet.',
    body: 'Choose FuseOS in any app on your phone. A link opens in one click on the Mac.',
  },
  {
    Icon: IconDeviceMobile,
    label: 'Linked',
    title: 'Always linked. Nothing to pair.',
    body: 'Sign in to the same account on both devices and they find each other on your Wi-Fi.',
  },
] as const;

// Timeline units. The Mac rises (0→1), the view zooms onto the notch (1→2), the island
// wakes (2→OPEN), then one unit per step.
const OPEN = 2.3;
const TOTAL = OPEN + STEPS.length + 0.4;

const MAC_FONT = {
  fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif',
};

/** A macOS-style wallpaper in the FuseOS palette: deep dusk with ember light rising. */
function Wallpaper() {
  return (
    <div className="absolute inset-0 overflow-hidden bg-[linear-gradient(180deg,#0b0d18_0%,#171133_42%,#3a1726_72%,#7a2e12_100%)]">
      <div className="absolute -bottom-[30%] -left-[10%] h-[80%] w-[70%] rounded-[50%] bg-[#ff7a45] opacity-70 blur-[60px]" />
      <div className="absolute -right-[15%] -bottom-[25%] h-[70%] w-[60%] rounded-[50%] bg-[#e85d2a] opacity-60 blur-[70px]" />
      <div className="absolute top-[10%] left-[30%] h-[50%] w-[50%] rounded-[50%] bg-[#4a2a8a] opacity-40 blur-[80px]" />
      <svg
        viewBox="0 0 400 200"
        preserveAspectRatio="none"
        className="absolute inset-x-0 bottom-0 h-[55%] w-full opacity-60 mix-blend-screen"
      >
        <path
          d="M0 140 C 80 90, 160 170, 240 120 S 360 80, 400 110 L 400 200 L 0 200 Z"
          fill="#ffb347"
          opacity=".35"
        />
        <path
          d="M0 165 C 90 130, 170 190, 260 150 S 360 120, 400 140 L 400 200 L 0 200 Z"
          fill="#ff7a45"
          opacity=".45"
        />
      </svg>
      <div className="absolute inset-0 bg-[linear-gradient(115deg,rgb(255_255_255/0.07),transparent_38%)]" />
    </div>
  );
}

/** The macOS menu bar, at the size it is drawn: `h` tall with text at `fs`. */
function MenuBar({
  h,
  fs,
  gap,
  compact,
}: {
  h: number;
  fs: number;
  gap: number;
  compact?: boolean;
}) {
  const icon = Math.round(fs * 1.15);
  return (
    <div
      style={{ height: h, fontSize: fs, ...MAC_FONT }}
      className="relative flex items-center justify-between bg-black/25 text-white/90 backdrop-blur-md"
    >
      <span className="flex items-center" style={{ gap, paddingLeft: gap }}>
        <IconBrandApple size={icon} className="text-white" />
        <b className="font-semibold text-white">Finder</b>
        {!compact && <span className="hidden text-white/80 sm:inline">File</span>}
        {!compact && <span className="hidden text-white/80 sm:inline">Edit</span>}
        {!compact && <span className="hidden text-white/80 md:inline">View</span>}
        {!compact && <span className="hidden text-white/80 md:inline">Go</span>}
        {!compact && <span className="hidden text-white/80 lg:inline">Window</span>}
      </span>
      <span className="flex items-center" style={{ gap, paddingRight: gap }}>
        <FuseMark className="text-white" />
        {!compact && <IconBattery3 size={icon + 4} className="hidden sm:inline" />}
        <IconWifi size={icon} />
        {!compact && <span className="hidden tabular-nums md:inline">Tue 22 Sep</span>}
        <span className="tabular-nums">9:41</span>
      </span>
    </div>
  );
}

/** A macOS window's chrome with a blank body, for depth on the desktop. */
function DesktopWindow({ className, title }: { className: string; title: string }) {
  return (
    <div
      className={cn(
        'absolute overflow-hidden rounded-[10px] border border-white/10 bg-[#1b1d24]/85 shadow-[0_20px_50px_-15px_rgb(0_0_0/0.8)] backdrop-blur-xl',
        className,
      )}
    >
      <div className="flex items-center gap-[6%] border-b border-white/5 bg-white/[0.03] px-[4%] py-[2.5%]">
        <span className="flex gap-[5px]">
          <i className="aspect-square w-[9px] rounded-full bg-[#ff5f57]" />
          <i className="aspect-square w-[9px] rounded-full bg-[#febc2e]" />
          <i className="aspect-square w-[9px] rounded-full bg-[#28c840]" />
        </span>
        <span className="text-[11px] text-white/50" style={MAC_FONT}>
          {title}
        </span>
      </div>
      <div className="grid gap-[8px] p-[5%]">
        <div className="h-[7px] w-2/3 rounded bg-white/10" />
        <div className="h-[7px] w-5/6 rounded bg-white/[0.07]" />
        <div className="h-[7px] w-1/2 rounded bg-white/[0.07]" />
      </div>
    </div>
  );
}

/**
 * A MacBook Pro, front on and at rest: aluminium edge, thin black bezel, rounded display,
 * the notch, and the base with its lip. The notch's top sits 12px below the lid's top,
 * which is where the camera pushes in.
 */
function MacBook() {
  return (
    <div className="relative w-[640px]">
      <div className="relative mx-auto aspect-[1.55] w-[580px] rounded-[22px] bg-[linear-gradient(150deg,#8a909b_0%,#3a3f48_22%,#1c1f25_60%,#565c67_100%)] p-[2px] shadow-[0_50px_120px_-40px_rgb(0_0_0/0.95)]">
        <div className="h-full w-full rounded-[20px] bg-black p-[10px]">
          <div className="relative h-full w-full overflow-hidden rounded-[11px]">
            <Wallpaper />
            <MenuBar h={14} fs={7.5} gap={8} compact />
            <div className="absolute top-0 left-1/2 z-10 h-[14px] w-[64px] -translate-x-1/2 rounded-b-[6px] bg-black" />
            <DesktopWindow className="top-[16%] left-[8%] w-[46%]" title="Notes" />
            <DesktopWindow className="top-[30%] right-[7%] w-[40%]" title="Downloads" />
            <div className="absolute bottom-[4%] left-1/2 flex -translate-x-1/2 gap-[6px] rounded-[12px] border border-white/10 bg-white/10 p-[5px] backdrop-blur-md">
              {['#ff7a45', '#4c8dff', '#34c759', '#ffcc00', '#af52de', '#eceff4'].map((c) => (
                <span
                  key={c}
                  className="h-[22px] w-[22px] rounded-[6px]"
                  style={{ background: `linear-gradient(145deg, ${c}, ${c}99)` }}
                />
              ))}
            </div>
          </div>
        </div>
      </div>
      <div className="relative -mt-[2px] h-[15px] w-full rounded-t-[3px] rounded-b-[18px] bg-[linear-gradient(180deg,#9aa0ab_0%,#4a4f59_30%,#23262d_70%,#121418_100%)]">
        <div className="absolute top-0 left-1/2 h-[6px] w-[118px] -translate-x-1/2 rounded-b-[9px] bg-[linear-gradient(180deg,#1b1e24,#3a3f48)]" />
      </div>
      <div className="mx-auto mt-3 h-6 w-[78%] rounded-[50%] bg-black/80 blur-2xl" />
    </div>
  );
}

/**
 * The camera's close-up of the top of that display, drawn at real size rather than
 * magnified — so the menu bar is crisp, and the notch is a real notch the island grows from.
 */
function CloseUp() {
  return (
    <div className="absolute inset-0">
      {/* aluminium edge, then the bezel's top strip */}
      <div className="h-px w-full bg-[linear-gradient(90deg,transparent,#8a909b_20%,#8a909b_80%,transparent)]" />
      <div className="h-[13px] w-full bg-black" />
      <div className="absolute inset-x-0 top-[14px] bottom-0 overflow-hidden">
        <Wallpaper />
        <MenuBar h={37} fs={13.5} gap={18} />
        <DesktopWindow className="top-[90px] left-[6%] w-[34%] opacity-70" title="Notes — Friday" />
        <DesktopWindow className="top-[150px] right-[5%] w-[30%] opacity-60" title="Downloads" />
        {/* fade the desktop into the page so the caption reads */}
        <div className="absolute inset-x-0 bottom-0 h-[60%] bg-gradient-to-b from-transparent via-void/80 to-void" />
      </div>
    </div>
  );
}

type IslandSize = { width: number; height: number; radius: number };

/** The island's shape and content for one step. At `null` it is just the notch. */
function IslandContent({ step, file, copied }: { step: number; file: number; copied?: string }) {
  const row = 'flex items-center gap-3.5';
  const tile =
    'grid h-12 w-12 shrink-0 place-items-center rounded-2xl bg-gradient-to-br from-ember to-ember-deep text-white shadow-[0_0_28px_-6px_rgb(255_122_69/0.8)]';
  const kicker = 'font-mono text-[10.5px] tracking-[0.1em] text-white/50 uppercase';

  if (copied !== undefined || step === 0) {
    return (
      <div className={row}>
        <span className={tile}>
          <IconClipboardCheck size={24} stroke={1.8} />
        </span>
        <div className="min-w-0 flex-1">
          <p className={kicker}>
            {copied !== undefined ? 'Copied on this Mac' : 'Copied on Pixel 8'}
          </p>
          <p className="truncate text-[16px] font-medium text-white">
            {copied ?? '4471 — buzz twice, 3rd floor'}
          </p>
        </div>
        <span className="rounded-full bg-white/10 px-2.5 py-1 font-mono text-[11px] text-white/80">
          ⌘V
        </span>
      </div>
    );
  }
  if (step === 1) {
    return (
      <div className={row}>
        <Photo className="h-16 w-[88px] shrink-0 rounded-xl" />
        <div className="min-w-0 flex-1">
          <p className={kicker}>Image from Pixel 8</p>
          <p className="truncate text-[16px] font-medium text-white">Screenshot 09:41</p>
          <p className="font-mono text-[11px] text-white/50">1.2 MB · on your clipboard</p>
        </div>
      </div>
    );
  }
  if (step === 2) {
    const done = file >= 1;
    return (
      <div className="grid gap-3">
        <div className={row}>
          <span className={tile}>
            <IconFileZip size={24} stroke={1.8} />
          </span>
          <div className="min-w-0 flex-1">
            <p className={kicker}>{done ? 'Saved to Downloads' : 'Receiving from Pixel 8'}</p>
            <p className="truncate text-[16px] font-medium text-white">trip-photos.zip</p>
          </div>
          <span className="font-mono text-[12px] text-white/70 tabular-nums">
            {done ? '✓ verified' : `${Math.round(file * 48)} / 48 MB`}
          </span>
        </div>
        <div className="h-1.5 overflow-hidden rounded-full bg-white/10">
          <div
            className="h-full rounded-full bg-gradient-to-r from-ember-deep to-amber"
            style={{ width: `${Math.round(file * 100)}%` }}
          />
        </div>
      </div>
    );
  }
  if (step === 3) {
    return (
      <div className={row}>
        <span className={tile}>
          <IconLink size={24} stroke={1.8} />
        </span>
        <div className="min-w-0 flex-1">
          <p className={kicker}>Shared from Chrome</p>
          <p className="truncate text-[16px] font-medium text-white">maps.app.goo.gl/tx8Qe</p>
        </div>
        <span className="flex shrink-0 gap-1.5">
          <span className="rounded-full bg-ember px-3 py-1.5 text-[12px] font-semibold text-white">
            Open
          </span>
          <span className="rounded-full bg-white/10 px-3 py-1.5 text-[12px] text-white/80">
            Copy
          </span>
        </span>
      </div>
    );
  }
  return (
    <div className={row}>
      <span className="flex items-center gap-2 text-white">
        <IconDeviceMobile size={26} stroke={1.6} />
        <span className="relative h-[2px] w-12 bg-white/20">
          <span className="absolute top-1/2 left-1/2 h-2 w-2 -translate-x-1/2 -translate-y-1/2 animate-ping rounded-full bg-ember" />
          <span className="absolute top-1/2 left-1/2 h-2 w-2 -translate-x-1/2 -translate-y-1/2 rounded-full bg-ember" />
        </span>
        <IconDeviceLaptop size={28} stroke={1.6} />
      </span>
      <div className="min-w-0 flex-1">
        <p className={kicker}>Linked · direct</p>
        <p className="truncate text-[16px] font-medium text-white">Pixel 8 ⇄ MacBook Air</p>
      </div>
      <span className="font-mono text-[12px] text-white/60">82%</span>
    </div>
  );
}

const SIZES: IslandSize[] = [
  { width: 470, height: 116, radius: 34 },
  { width: 450, height: 124, radius: 34 },
  { width: 480, height: 138, radius: 36 },
  { width: 480, height: 116, radius: 34 },
  { width: 440, height: 110, radius: 32 },
];

/**
 * The island, grown out of the notch. Its top edge is flat and flush with the notch, and
 * two inverted corners ("shoulders") melt it into the menu bar, the way macOS notch apps do.
 */
function NotchIsland({
  open,
  step,
  file,
  notch,
}: {
  open: boolean;
  step: number;
  file: number;
  notch: { width: number; height: number };
}) {
  const reduce = useReducedMotion();
  const event = useIsland();
  const copied = open && event?.kind === 'clip' ? event.detail : undefined;
  const target = copied !== undefined ? SIZES[0] : SIZES[step];
  const size = open
    ? {
        width: `min(${target.width}px, calc(100vw - 32px))`,
        height: target.height,
        r: target.radius,
      }
    : { width: `${notch.width}px`, height: notch.height, r: 12 };

  return (
    <div className="pointer-events-none absolute top-0 left-1/2 z-30 -translate-x-1/2">
      <motion.div
        initial={false}
        animate={{
          width: size.width,
          height: size.height,
          borderBottomLeftRadius: size.r,
          borderBottomRightRadius: size.r,
        }}
        transition={reduce ? { duration: 0 } : { type: 'spring', bounce: 0.2, duration: 0.85 }}
        className="relative bg-black shadow-[inset_0_-1px_0_rgb(255_255_255/0.07),0_30px_60px_-20px_rgb(0_0_0/0.9)]"
      >
        {/* shoulders */}
        <span className="absolute top-0 -left-2.5 h-2.5 w-2.5 bg-[radial-gradient(circle_at_0_100%,transparent_10px,#000_10.5px)]" />
        <span className="absolute top-0 -right-2.5 h-2.5 w-2.5 bg-[radial-gradient(circle_at_100%_100%,transparent_10px,#000_10.5px)]" />
        <div className="absolute inset-0 overflow-hidden">
          <AnimatePresence mode="popLayout" initial={false}>
            {open && (
              <motion.div
                key={copied !== undefined ? 'copied' : step}
                initial={{ opacity: 0, filter: 'blur(10px)', y: -10, scale: 0.96 }}
                animate={{ opacity: 1, filter: 'blur(0px)', y: 0, scale: 1 }}
                exit={{ opacity: 0, filter: 'blur(10px)', y: -6, scale: 0.97 }}
                transition={{ duration: 0.32, delay: 0.1 }}
                className="absolute inset-x-0 bottom-0 px-6 pb-5"
              >
                <IslandContent step={step} file={file} copied={copied} />
              </motion.div>
            )}
          </AnimatePresence>
        </div>
      </motion.div>
    </div>
  );
}

/**
 * The notch section: a pinned stage where a MacBook rises, the camera flies into its
 * notch, and the Dynamic Island opens out of it — then each stretch of scroll turns it
 * into the next thing FuseOS moves.
 */
export function NotchStage() {
  const root = useRef<HTMLElement>(null);
  const trigger = useRef<ScrollTrigger | null>(null);
  const [open, setOpen] = useState(false);
  const [step, setStep] = useState(0);
  const [file, setFile] = useState(0);
  // The close-up's notch, at real size. The MacBook's notch is 64px wide, so the camera
  // push ends at this over 64 — and the two notches line up as they cross-fade.
  const [notch, setNotch] = useState({ width: 190, height: 37 });

  // Copy anything on this page and the island shows it, the way the Mac app does.
  useEffect(() => {
    const onCopy = () => {
      const text = window.getSelection()?.toString().trim();
      if (text) pushIsland({ kind: 'clip', title: 'Copied', detail: text, from: 'mac' });
    };
    document.addEventListener('copy', onCopy);
    return () => document.removeEventListener('copy', onCopy);
  }, []);

  useEffect(() => {
    const query = window.matchMedia('(min-width: 768px)');
    const update = () =>
      setNotch(query.matches ? { width: 190, height: 37 } : { width: 124, height: 28 });
    update();
    query.addEventListener('change', update);
    return () => query.removeEventListener('change', update);
  }, []);

  useGSAP(
    () => {
      const mm = gsap.matchMedia();
      mm.add(
        {
          wide: '(min-width: 768px)',
          motion: '(prefers-reduced-motion: no-preference)',
        },
        (ctx) => {
          const { wide, motion: moving } = ctx.conditions as { wide: boolean; motion: boolean };
          const base = wide ? 1 : 0.55;
          const end = (wide ? 190 : 124) / 64;
          gsap.set('.mac-rig', { xPercent: -50, transformOrigin: '50% 12px' });
          gsap.set('.closeup', { transformOrigin: '50% 0%' });

          if (!moving) {
            gsap.set('.mac-rig', { opacity: 0 });
            gsap.set('.notch-intro', { opacity: 0 });
            gsap.set('.closeup', { opacity: 1 });
            setOpen(true);
            return;
          }

          const tl = gsap.timeline({
            defaults: { ease: 'none' },
            scrollTrigger: {
              trigger: '.notch-pin',
              start: 'top top',
              end: '+=4800',
              pin: true,
              scrub: 1.2,
              onUpdate: (self) => {
                const t = self.progress * TOTAL;
                setOpen(t >= OPEN);
                const s = Math.min(STEPS.length - 1, Math.max(0, Math.floor(t - OPEN)));
                setStep(s);
                // The file fills across the first 80% of its own stretch, then holds.
                const f = s === 2 ? Math.min(1, Math.max(0, (t - OPEN - 2) / 0.8)) : s > 2 ? 1 : 0;
                // Whole percents: a scroll frame re-renders only when the bar actually moves.
                setFile(Math.round(f * 100) / 100);
              },
            },
          });
          trigger.current = tl.scrollTrigger ?? null;
          // 0 → 1: the MacBook rises and settles, tipping up from below.
          tl.fromTo(
            '.mac-rig',
            { y: '65vh', scale: base * 0.9, opacity: 0, rotationX: 22, transformPerspective: 1600 },
            { y: 0, scale: base, opacity: 1, rotationX: 0, duration: 1, ease: 'power3.out' },
          )
            .to('.notch-intro', { opacity: 0, y: -30, duration: 0.5 }, 1)
            // 1 → 2: the camera pushes into the notch. The MacBook grows until its notch is
            // the close-up's size, fading out as the crisp close-up fades in over it.
            .to('.mac-rig', { scale: end, duration: 1, ease: 'power2.in' }, 1)
            .to('.mac-rig', { opacity: 0, duration: 0.35, ease: 'power1.in' }, 1.62)
            .fromTo(
              '.closeup',
              { opacity: 0, scale: 1.08 },
              { opacity: 1, scale: 1, duration: 0.55, ease: 'power2.out' },
              1.5,
            )
            .fromTo('.notch-glow', { opacity: 0 }, { opacity: 1, duration: 0.4 }, 2)
            .to({}, { duration: TOTAL - 2 });
        },
      );
    },
    { scope: root },
  );

  /** Rail click: scroll to the middle of that step's stretch. */
  const goTo = (i: number) => {
    const st = trigger.current;
    if (!st) return setStep(i);
    const y = st.start + ((OPEN + i + 0.5) / TOTAL) * (st.end - st.start);
    scrollToY(y);
  };

  const current = STEPS[step];

  return (
    <section id="notch" ref={root} className="relative bg-void">
      <div className="notch-pin relative h-screen overflow-hidden">
        <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(60%_50%_at_50%_30%,rgb(255_122_69/0.12),transparent_70%)]" />

        <div className="notch-intro pointer-events-none absolute inset-x-0 bottom-[10vh] z-10 px-4 text-center">
          <p className="font-mono text-xs tracking-[0.14em] text-ember uppercase">
            Once they’re linked
          </p>
          <h2 className="mx-auto mt-4 max-w-[16ch] font-display text-[clamp(38px,6vw,76px)] leading-[0.95] font-black tracking-[-0.045em]">
            Your phone lives in your Mac’s notch.
          </h2>
        </div>

        {/* The anchor: the notch's top edge sits here for the whole ride. */}
        <div className="absolute inset-x-0 top-[96px] bottom-0 md:top-[88px]">
          <div className="closeup absolute inset-x-0 -top-[14px] bottom-0 opacity-0 will-change-transform">
            <CloseUp />
            <div className="notch-glow pointer-events-none absolute top-[14px] left-1/2 h-72 w-[620px] max-w-[100vw] -translate-x-1/2 bg-[radial-gradient(50%_60%_at_50%_0%,rgb(255_122_69/0.30),transparent_70%)] opacity-0" />
            <div className="absolute top-[14px] left-0 w-full">
              <NotchIsland open={open} step={step} file={file} notch={notch} />
            </div>
          </div>
          <div className="mac-rig absolute -top-[12px] left-1/2 opacity-0 will-change-transform">
            <MacBook />
          </div>
        </div>

        {/* Caption for the step the island is on. */}
        <div className="absolute inset-x-0 bottom-[9vh] z-20 px-4 text-center">
          <AnimatePresence mode="wait">
            {open && (
              <motion.div
                key={step}
                initial={{ opacity: 0, y: 18 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -12 }}
                transition={{ duration: 0.3 }}
                className="mx-auto max-w-2xl rounded-3xl border border-white/10 bg-[#0c0e14]/70 px-6 py-5 backdrop-blur-xl"
              >
                <p className="flex items-center justify-center gap-2 font-mono text-xs tracking-[0.14em] text-ember uppercase">
                  <current.Icon size={15} /> {String(step + 1).padStart(2, '0')} / 05 ·{' '}
                  {current.label}
                </p>
                <h3 className="mt-2 font-display text-[clamp(24px,3vw,36px)] leading-tight font-black tracking-[-0.03em]">
                  {current.title}
                </h3>
                <p className="mx-auto mt-2 max-w-[54ch] text-muted">{current.body}</p>
              </motion.div>
            )}
          </AnimatePresence>
        </div>

        {/* Rail: where you are, and a way to jump. */}
        <ol className="absolute top-1/2 left-6 z-20 hidden -translate-y-1/2 gap-1 lg:grid">
          {STEPS.map((s, i) => (
            <li key={s.label}>
              <button
                type="button"
                onClick={() => goTo(i)}
                className={cn(
                  'flex items-center gap-3 rounded-full py-1.5 pr-4 pl-2 text-left text-[13px] transition-colors',
                  open && i === step ? 'text-ink' : 'text-muted/60 hover:text-muted',
                )}
              >
                <span
                  className={cn(
                    'h-8 w-[3px] rounded-full transition-colors',
                    open && i === step ? 'bg-ember' : 'bg-white/10',
                  )}
                />
                <s.Icon size={15} />
                {s.label}
              </button>
            </li>
          ))}
        </ol>
      </div>
    </section>
  );
}
