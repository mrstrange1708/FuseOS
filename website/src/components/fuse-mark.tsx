import { cn } from '@/lib/utils';

/** The FuseOS mark: two devices joined by a filament. Same geometry as the apps' FuseMark. */
export function FuseMark({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 40 22" className={cn('h-[22px] w-10', className)} aria-hidden="true">
      <line
        x1="7"
        y1="11"
        x2="33"
        y2="11"
        stroke="currentColor"
        strokeOpacity=".4"
        strokeWidth="2.2"
      />
      <circle cx="20" cy="11" r="2.4" fill="#FF7A45" />
      <circle cx="7" cy="11" r="4.8" fill="none" stroke="currentColor" strokeWidth="2.2" />
      <circle cx="33" cy="11" r="4.8" fill="#FF7A45" />
    </svg>
  );
}

export function Wordmark() {
  return (
    <span className="flex items-center gap-2.5 font-mono text-[17px] font-bold text-ink">
      <FuseMark />
      <span>
        Fuse<span className="font-medium text-muted">OS</span>
      </span>
    </span>
  );
}
