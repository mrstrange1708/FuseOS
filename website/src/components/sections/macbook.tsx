'use client';

import { MacbookScroll } from '@/components/ui/macbook-scroll';
import { MacAppScreen } from '@/components/devices';
import { FuseMark } from '@/components/fuse-mark';

/** Aceternity's MacBook, lid opening on scroll onto the real FuseOS Mac app. */
export function MacbookSection() {
  return (
    <section aria-label="FuseOS on the Mac" className="relative w-full overflow-hidden bg-void">
      <MacbookScroll
        showGradient
        badge={<FuseMark className="h-5 w-9 text-white" />}
        title={
          <span className="font-display text-[clamp(28px,4vw,48px)] font-black tracking-[-0.03em] text-ink">
            Open your Mac.
            <br />
            <span className="text-muted">What you copied on your phone is already there.</span>
          </span>
        }
      >
        <MacAppScreen />
      </MacbookScroll>
    </section>
  );
}
