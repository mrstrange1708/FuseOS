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

const SIDEBAR = [
  { label: 'Home', Icon: IconLayoutGrid, active: true },
  { label: 'History', Icon: IconClock },
  { label: 'Devices', Icon: IconDeviceLaptop },
  { label: 'Screen', Icon: IconScreenShare },
  { label: 'Account', Icon: IconUserCircle },
];

/**
 * The FuseOS Mac app's Home pane, as it really looks: sidebar, devices, the Files drop
 * zone with a transfer in flight, and the recent clips. Sized for the MacBook's lid.
 */
export function MacAppScreen() {
  return (
    <div className="flex h-full w-full bg-[#0c0e14] text-[#eceff4]">
      <aside className="flex w-[96px] shrink-0 flex-col border-r border-white/5 bg-[#10131a] px-2 pt-6 pb-2">
        <div className="mb-3 flex gap-1 px-1">
          <i className="h-[7px] w-[7px] rounded-full bg-[#ff5f57]" />
          <i className="h-[7px] w-[7px] rounded-full bg-[#febc2e]" />
          <i className="h-[7px] w-[7px] rounded-full bg-[#28c840]" />
        </div>
        {SIDEBAR.map(({ label, Icon, active }) => (
          <span
            key={label}
            className={cn(
              'mb-0.5 flex items-center gap-1.5 rounded-md px-1.5 py-1 text-[8.5px]',
              active ? 'bg-white/10 text-white' : 'text-white/55',
            )}
          >
            <Icon size={10} /> {label}
          </span>
        ))}
        <span className="mt-auto flex items-center gap-1.5 px-1.5 font-mono text-[7.5px] text-white/50">
          <i className="h-1.5 w-1.5 rounded-full bg-ember" /> Linked
        </span>
      </aside>

      <main className="flex min-w-0 flex-1 flex-col gap-2.5 px-4 pt-5">
        <div>
          <p className="font-display text-[15px] font-bold">Home</p>
          <p className="text-[7.5px] text-white/50">
            Clipboard and files are moving directly over your network.
          </p>
        </div>

        <div className="flex items-center gap-2 rounded-lg border border-white/5 bg-[#161922] px-2.5 py-1.5">
          <IconDeviceMobile size={13} className="text-ember" />
          <div className="flex-1">
            <p className="text-[8.5px] font-semibold">Pixel 8</p>
            <p className="font-mono text-[6.5px] text-white/45">android · connected · direct</p>
          </div>
          <span className="font-mono text-[7px] text-white/50">82%</span>
        </div>

        <p className="text-[8.5px] font-semibold">Files</p>
        <div className="grid place-items-center gap-0.5 rounded-lg border border-dashed border-ember/60 bg-ember/[0.06] py-2 text-center">
          <IconArrowUp size={12} className="text-ember" />
          <p className="text-[7.5px]">Drop files to send them to Pixel 8</p>
        </div>
        <div className="flex items-center gap-2 rounded-lg border border-white/5 bg-[#161922] px-2.5 py-1.5">
          <span className="font-mono text-[9px] text-ember">↓</span>
          <div className="flex-1">
            <p className="text-[8px]">trip-photos.zip</p>
            <p className="font-mono text-[6.5px] text-white/45">Receiving from Pixel 8 · 64%</p>
            <div className="mt-1 h-[3px] overflow-hidden rounded-full bg-white/10">
              <div className="h-full w-[64%] rounded-full bg-gradient-to-r from-ember-deep to-amber" />
            </div>
          </div>
        </div>

        <p className="text-[8.5px] font-semibold">Recent</p>
        {['4471 — buzz twice, 3rd floor', 'https://maps.app.goo.gl/tx8Qe'].map((clip, i) => (
          <div key={clip} className="rounded-lg border border-white/5 bg-[#161922] px-2.5 py-1.5">
            <p className="font-mono text-[6.5px] text-ember">
              {i === 0 ? 'From Pixel 8' : 'Copied here'}
            </p>
            <p className="truncate text-[8px]">{clip}</p>
          </div>
        ))}
      </main>
    </div>
  );
}

/** The phone-side counterpart: the FuseOS Android home, linked and receiving. */
export function AndroidAppScreen() {
  return (
    <div className="flex h-full flex-col gap-3 px-4 pt-4 text-white">
      <div className="flex items-center gap-2">
        <FuseMark className="h-3 w-6 text-white" />
        <span className="font-mono text-[11px] font-bold">
          Fuse<span className="font-medium text-white/50">OS</span>
        </span>
      </div>
      <div className="flex items-center gap-2 rounded-2xl bg-ember/15 px-3 py-2.5 text-[11px] font-medium text-ember">
        <i className="h-2 w-2 rounded-full bg-ember" /> Linked to MacBook Air
      </div>
      <p className="text-[12px] font-semibold">Recent</p>
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
