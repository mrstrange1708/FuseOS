import { IconDownload } from '@tabler/icons-react';

// Plain asset URLs don't get next.config's basePath (the Pages build lives under /FuseOS).
const BASE = process.env.NEXT_PUBLIC_BASE_PATH ?? '';

/** The launch film: everything FuseOS does, in 36 seconds. */
export function Film() {
  return (
    <section id="film" className="relative overflow-hidden bg-void py-24">
      <div className="pointer-events-none absolute top-1/3 left-1/2 h-[520px] w-[1000px] -translate-x-1/2 rounded-full bg-ember/[0.08] blur-[140px]" />
      <div className="relative mx-auto max-w-6xl px-4 sm:px-6">
        <p className="font-mono text-xs uppercase tracking-[0.14em] text-ember">
          Watch · 36 seconds
        </p>
        <h2 className="mt-4 max-w-[18ch] font-display text-[clamp(36px,5vw,64px)] leading-[0.98] font-black tracking-[-0.04em]">
          Your phone and your Mac, as one.
        </h2>
        <p className="mt-5 max-w-[56ch] text-lg text-muted">
          Copy, files, notifications, calls, your phone&apos;s screen — everything FuseOS does,
          straight over your Wi-Fi.
        </p>
        <div className="mt-10 overflow-hidden rounded-3xl border border-white/[0.08] bg-[#0e1017] shadow-[0_40px_120px_-40px_rgba(255,122,69,0.35)]">
          <video
            className="block aspect-video w-full"
            src={`${BASE}/fuseos-film.mp4`}
            poster={`${BASE}/fuseos-film.jpg`}
            controls
            playsInline
            preload="metadata"
            aria-label="FuseOS launch film"
          />
        </div>
        <a
          href={`${BASE}/fuseos-film-1080p.mp4`}
          download="FuseOS-film-1080p.mp4"
          className="mt-4 inline-flex items-center gap-2 text-sm text-muted transition-colors hover:text-ink"
        >
          <IconDownload size={16} /> Download the full-quality film (1080p, 15 MB)
        </a>
      </div>
    </section>
  );
}
