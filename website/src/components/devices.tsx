import type { ReactNode } from 'react';
import {
  IconArrowUp,
  IconBattery3,
  IconClock,
  IconDeviceLaptop,
  IconDeviceMobile,
  IconLayoutGrid,
  IconUserCircle,
  IconWifi,
  IconScreenShare,
} from '@tabler/icons-react';
import { cn } from '@/lib/utils';
import { FuseMark } from '@/components/fuse-mark';

/**
 * An Android phone in the Pixel idiom: flat rails, a centred punch-hole, buttons on the
 * right. Drawn rather than photographed so the screen can hold live content.
 */
export function PixelPhone({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <div
      className={cn(
        'relative aspect-[9/19.5] w-[260px] rounded-[46px] p-[10px]',
        'bg-[linear-gradient(145deg,#3a404d,#14171f_40%,#262b36)]',
        'shadow-[0_0_0_1px_rgb(255_255_255/0.08),0_40px_80px_-30px_rgb(0_0_0/0.9),inset_0_0_0_2px_rgb(0_0_0/0.6)]',
        className,
      )}
    >
      {/* side buttons */}
      <span className="absolute top-[22%] -right-[3px] h-14 w-[3px] rounded-r bg-[#2b303b]" />
      <span className="absolute top-[36%] -right-[3px] h-24 w-[3px] rounded-r bg-[#2b303b]" />
      <div className="relative h-full w-full overflow-hidden rounded-[37px] bg-[#05060a]">
        <div className="absolute top-3 left-1/2 z-20 h-3.5 w-3.5 -translate-x-1/2 rounded-full bg-black shadow-[0_0_0_2px_#15181f]" />
        <div className="relative z-10 flex items-center justify-between px-6 pt-3 font-mono text-[10px] text-white/80">
          <span>9:41</span>
          <span className="flex items-center gap-1">
            <IconWifi size={11} />
            <IconBattery3 size={13} />
          </span>
        </div>
        <div className="h-[calc(100%-26px)]">{children}</div>
      </div>
    </div>
  );
}

const NAV = [
  { label: 'Home', Icon: IconLayoutGrid, active: true },
  { label: 'History', Icon: IconClock },
  { label: 'Devices', Icon: IconDeviceLaptop },
  { label: 'Screen', Icon: IconScreenShare },
  { label: 'Account', Icon: IconUserCircle },
];

/**
 * The line between two devices as both apps draw it: a rail, a resting dot, and a comet
 * with an amber tail crossing it (CSS `comet` in globals.css), landing on the far side.
 */
function Filament({ className }: { className?: string }) {
  return (
    <span className={cn('relative block h-3 flex-1', className)}>
      <i className="absolute inset-x-0 top-1/2 h-px -translate-y-1/2 bg-gradient-to-r from-ember/15 via-ember/55 to-ember/15" />
      <i className="comet absolute top-1/2 h-[2px] w-[30%] -translate-y-1/2 rounded-full bg-gradient-to-r from-transparent to-amber shadow-[0_0_8px_#ffb347]" />
    </span>
  );
}

/**
 * The FuseOS Mac app's Home, as it really looks: the floating glass nav, the glowing link
 * hero with a spark crossing, then clipboard beside what the phone is doing and files.
 * Sized for the MacBook's lid.
 */
export function MacAppScreen() {
  return (
    <div className="relative flex h-full w-full flex-col gap-2 bg-[#0c0e14] px-3 pt-2 text-[#eceff4]">
      <div className="pointer-events-none absolute inset-x-0 top-0 h-24 bg-[radial-gradient(ellipse_at_top,rgb(255_122_69/0.18),transparent_70%)]" />
      <div className="relative flex items-center">
        <div className="flex gap-1">
          <i className="h-[6px] w-[6px] rounded-full bg-[#ff5f57]" />
          <i className="h-[6px] w-[6px] rounded-full bg-[#febc2e]" />
          <i className="h-[6px] w-[6px] rounded-full bg-[#28c840]" />
        </div>
        <nav className="mx-auto flex items-center gap-1 rounded-full border border-white/10 bg-white/[0.04] px-1 py-0.5 backdrop-blur">
          {NAV.map(({ label, Icon, active }) =>
            active ? (
              <span
                key={label}
                className="flex items-center gap-1 rounded-full bg-ember/15 px-1.5 py-0.5 text-[7px] text-ember"
              >
                <Icon size={8} /> {label}
              </span>
            ) : (
              <Icon key={label} size={8} className="mx-0.5 text-white/55" />
            ),
          )}
        </nav>
      </div>

      <div className="relative flex items-center gap-3 rounded-xl border border-ember/35 bg-[#161922] px-3 py-2 shadow-[0_0_30px_-14px_rgb(255_122_69/0.7)]">
        <div className="flex w-[42%] items-center">
          <span className="grid h-6 w-6 place-items-center rounded-full bg-ember/15 text-ember">
            <IconDeviceLaptop size={11} />
          </span>
          <Filament className="mx-1" />
          <span className="grid h-6 w-6 place-items-center rounded-full bg-ember/15 text-ember">
            <IconDeviceMobile size={11} />
          </span>
        </div>
        <div className="min-w-0 flex-1">
          <span className="rounded-full bg-ember/15 px-1.5 py-px font-mono text-[5.5px] text-ember">
            Linked · direct
          </span>
          <p className="hero-grad mt-0.5 font-display text-[12px] font-bold">Pixel 8</p>
          <p className="font-mono text-[6px] text-white/45">82% · 38 ms · p95 64 ms</p>
        </div>
      </div>

      <div className="grid flex-1 grid-cols-[1.3fr_1fr] gap-2 pb-2">
        <div className="rounded-xl border border-white/5 bg-[#161922] px-2.5 py-2">
          <p className="text-[8px] font-semibold">Clipboard</p>
          {[
            '4471 — buzz twice, 3rd floor',
            'https://maps.app.goo.gl/tx8Qe',
            'ssh deploy@10.0.4.12',
          ].map((clip, i) => (
            <div key={clip} className="mt-1.5 flex items-center gap-1.5">
              <i className="h-3.5 w-3.5 shrink-0 rounded bg-ember/15" />
              <div className="min-w-0">
                <p className="truncate text-[7px]">{clip}</p>
                <p className="font-mono text-[5.5px] text-white/45">
                  {i === 1 ? 'Copied here' : 'From Pixel 8'}
                </p>
              </div>
            </div>
          ))}
        </div>
        <div className="flex flex-col gap-2">
          <div className="flex items-center gap-1.5 rounded-xl border border-white/5 bg-[#161922] px-2 py-1.5">
            <Photo className="h-5 w-5 shrink-0 rounded" />
            <div className="min-w-0 flex-1">
              <p className="truncate text-[7px] font-semibold">Midnight City</p>
              <p className="font-mono text-[5.5px] text-white/45">M83</p>
            </div>
            <i className="h-3.5 w-3.5 rounded-full bg-ember" />
          </div>
          <div className="rounded-xl border border-white/5 bg-[#161922] px-2 py-1.5">
            <p className="flex items-center gap-1 text-[7px]">
              <IconArrowUp size={8} className="rotate-180 text-ember" /> trip-photos.zip
            </p>
            <div className="mt-1 h-[3px] overflow-hidden rounded-full bg-white/10">
              <div className="h-full w-[64%] rounded-full bg-gradient-to-r from-ember-deep to-amber" />
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

/** The phone-side counterpart: the FuseOS Android home — the same glowing link hero. */
export function AndroidAppScreen() {
  return (
    <div className="relative flex h-full flex-col gap-3 px-4 pt-4 text-white">
      <div className="pointer-events-none absolute inset-x-0 top-0 h-32 bg-[radial-gradient(ellipse_at_top,rgb(255_122_69/0.2),transparent_70%)]" />
      <div className="relative flex items-center gap-2">
        <FuseMark className="h-3 w-6 text-white" />
        <span className="font-mono text-[11px] font-bold">
          Fuse<span className="font-medium text-white/50">OS</span>
        </span>
      </div>
      <div className="relative rounded-3xl border border-ember/35 bg-white/[0.04] px-3 py-3 text-center shadow-[0_0_30px_-14px_rgb(255_122_69/0.7)]">
        <div className="flex items-center">
          <span className="grid h-8 w-8 place-items-center rounded-full bg-ember/15 text-ember">
            <IconDeviceMobile size={14} />
          </span>
          <Filament className="mx-1.5" />
          <span className="grid h-8 w-8 place-items-center rounded-full bg-ember/15 text-ember">
            <IconDeviceLaptop size={14} />
          </span>
        </div>
        <span className="mt-2 inline-block rounded-full bg-ember/15 px-2 py-0.5 font-mono text-[8px] text-ember">
          Linked · direct
        </span>
        <p className="hero-grad mt-1 font-display text-[15px] font-bold">MacBook Air</p>
      </div>
      <p className="text-[12px] font-semibold">Clipboard</p>
      {['4471 — buzz twice, 3rd floor', 'Image', 'https://maps.app.goo.gl/tx8Qe'].map((c, i) => (
        <div key={c} className="rounded-2xl border border-white/10 bg-white/[0.04] px-3 py-2">
          <p className="font-mono text-[8.5px] text-ember">
            {i === 1 ? 'From MacBook Air' : 'Copied here'}
          </p>
          <p className="truncate text-[11px]">{c}</p>
        </div>
      ))}
    </div>
  );
}

/** A sunset drawn in CSS, standing in for the photo that gets copied. */
export function Photo({ className }: { className?: string }) {
  return (
    <div
      className={`relative overflow-hidden rounded-xl bg-[linear-gradient(180deg,#2a1b3d_0%,#e85d2a_62%,#ffb347_100%)] ${className ?? ''}`}
    >
      <div className="absolute top-[34%] left-1/2 aspect-square h-[26%] -translate-x-1/2 rounded-full bg-[#ffd3bc] shadow-[0_0_40px_10px_rgb(255_179_71/0.6)]" />
      <div className="absolute inset-x-0 bottom-0 h-1/2 bg-[#14171f] [clip-path:polygon(0_60%,22%_20%,40%_55%,62%_10%,82%_50%,100%_30%,100%_100%,0_100%)]" />
    </div>
  );
}

/**
 * A macOS wallpaper in the manner of Apple's own (Sequoia's blue waves): deep navy rising
 * into Apple blue, with soft light-blue swells. Restrained on purpose; the orange belongs
 * to FuseOS, not to the Mac.
 */
export function MacWallpaper() {
  return (
    <div className="absolute inset-0 overflow-hidden bg-[linear-gradient(180deg,#050b1c_0%,#0a1a3d_38%,#0f3a86_72%,#2a6fd8_100%)]">
      <div className="absolute -bottom-[35%] -left-[15%] h-[85%] w-[75%] rounded-[50%] bg-[#3d8bff] opacity-45 blur-[48px]" />
      <div className="absolute -right-[20%] -bottom-[30%] h-[75%] w-[65%] rounded-[50%] bg-[#1b58c9] opacity-60 blur-[52px]" />
      <div className="absolute top-[5%] left-[35%] h-[45%] w-[45%] rounded-[50%] bg-[#123a8c] opacity-50 blur-[60px]" />
      <svg
        viewBox="0 0 400 200"
        preserveAspectRatio="none"
        className="absolute inset-x-0 bottom-0 h-[58%] w-full"
      >
        <defs>
          <linearGradient id="mac-wave-a" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="#9cc8ff" stopOpacity=".55" />
            <stop offset="1" stopColor="#2a6fd8" stopOpacity="0" />
          </linearGradient>
          <linearGradient id="mac-wave-b" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="#5aa2ff" stopOpacity=".6" />
            <stop offset="1" stopColor="#0f3a86" stopOpacity="0" />
          </linearGradient>
        </defs>
        <path
          d="M0 120 C 90 70, 170 160, 260 105 S 370 70, 400 95 L 400 200 L 0 200 Z"
          fill="url(#mac-wave-a)"
        />
        <path
          d="M0 155 C 100 115, 180 185, 270 140 S 370 115, 400 132 L 400 200 L 0 200 Z"
          fill="url(#mac-wave-b)"
        />
      </svg>
      <div className="absolute inset-0 bg-[linear-gradient(115deg,rgb(255_255_255/0.06),transparent_38%)]" />
    </div>
  );
}
