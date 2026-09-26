import type Lenis from 'lenis';

let lenis: Lenis | null = null;

/** Set by SmoothScroll; null when smoothing is off (reduced motion) or not mounted yet. */
export function setLenis(instance: Lenis | null) {
  lenis = instance;
}

/** Scrolls to a page offset through Lenis when it is running, natively otherwise. */
export function scrollToY(y: number) {
  if (lenis) lenis.scrollTo(y, { duration: 1.2 });
  else window.scrollTo({ top: y, behavior: 'smooth' });
}
