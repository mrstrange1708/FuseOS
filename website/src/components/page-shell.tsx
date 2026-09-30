import type { ReactNode } from 'react';
import { Navbar } from '@/components/navbar';
import { Footer } from '@/components/sections/chrome';
import { cn } from '@/lib/utils';

/** Every page but the home page: the same bar, a heading block, the content, the footer. */
export function PageShell({
  eyebrow,
  title,
  intro,
  children,
  narrow = true,
}: {
  eyebrow: string;
  title: ReactNode;
  intro?: ReactNode;
  children: ReactNode;
  /** Reading pages (policies, help) keep a comfortable line length. */
  narrow?: boolean;
}) {
  return (
    <>
      <Navbar />
      <main className="relative overflow-hidden bg-void pt-36 pb-28">
        <div className="pointer-events-none absolute top-0 left-1/2 h-[420px] w-[900px] -translate-x-1/2 rounded-full bg-ember/10 blur-[140px]" />
        <div className={cn('relative mx-auto px-4 sm:px-6', narrow ? 'max-w-3xl' : 'max-w-6xl')}>
          <p className="font-mono text-xs uppercase tracking-[0.14em] text-ember">{eyebrow}</p>
          <h1 className="mt-4 font-display text-[clamp(38px,5.6vw,68px)] leading-[0.98] font-black tracking-[-0.04em]">
            {title}
          </h1>
          {intro && <p className="mt-5 max-w-[60ch] text-lg text-muted">{intro}</p>}
          <div className="mt-14">{children}</div>
        </div>
      </main>
      <Footer />
    </>
  );
}

/** Long-form text (policies, help): headings, paragraphs, lists and links styled once. */
export function Prose({ children }: { children: ReactNode }) {
  return (
    <div
      className={cn(
        'max-w-[68ch] text-[16.5px] leading-relaxed text-muted',
        '[&_h2]:mt-12 [&_h2]:mb-4 [&_h2]:font-display [&_h2]:text-2xl [&_h2]:font-extrabold [&_h2]:tracking-[-0.02em] [&_h2]:text-ink',
        '[&_h3]:mt-8 [&_h3]:mb-2 [&_h3]:text-lg [&_h3]:font-semibold [&_h3]:text-ink',
        '[&_p]:mb-4 [&_ul]:mb-4 [&_ul]:list-disc [&_ul]:space-y-2 [&_ul]:pl-5 [&_ol]:mb-4 [&_ol]:list-decimal [&_ol]:space-y-2 [&_ol]:pl-5',
        '[&_b]:font-semibold [&_b]:text-ink [&_a]:text-ember [&_a]:underline-offset-4 hover:[&_a]:underline',
        '[&_h2]:scroll-mt-28 [&_h3]:scroll-mt-28',
      )}
    >
      {children}
    </div>
  );
}
