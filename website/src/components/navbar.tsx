'use client';

import { useEffect, useState } from 'react';
import { IconBrandGithub } from '@tabler/icons-react';
import { FuseMark, Wordmark } from '@/components/fuse-mark';
import { cn } from '@/lib/utils';

const LINKS = [
  { href: '#notch', label: 'The island' },
  { href: '#story', label: 'How it feels' },
  { href: '#menubar', label: 'Menu bar' },
  { href: '#privacy', label: 'Privacy' },
];

/** A glass pill across the top. It darkens once the page moves, so text never shows through. */
export function Navbar() {
  const [scrolled, setScrolled] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 24);
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  return (
    <header className="fixed inset-x-0 top-3 z-50 px-3">
      <nav
        aria-label="Primary"
        className={cn(
          'mx-auto flex h-14 max-w-6xl items-center justify-between gap-3 rounded-full pr-2 pl-5',
          'border border-white/10 backdrop-blur-xl backdrop-saturate-150 transition-[background-color] duration-300',
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

        <div className="flex items-center gap-1 text-[14px] text-muted">
          {LINKS.map((l) => (
            <a
              key={l.href}
              className="hidden rounded-full px-3 py-2 transition-colors hover:bg-white/5 hover:text-ink md:inline"
              href={l.href}
            >
              {l.label}
            </a>
          ))}
          <a
            className="rounded-full p-2 transition-colors hover:bg-white/5 hover:text-ink"
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
