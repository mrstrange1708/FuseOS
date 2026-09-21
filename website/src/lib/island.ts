'use client';

import { useSyncExternalStore } from 'react';

/**
 * What the Dynamic Island can show. The website drives it with demo events today; the
 * shape is the one a real FuseOS event source (the apps, or a companion page wired to
 * them) would push later — call `pushIsland` from anywhere and the island plays it.
 */
export type IslandEvent = {
  kind: 'clip' | 'image' | 'file' | 'link' | 'notification';
  /** Short headline, e.g. "Copied on Pixel 8". */
  title: string;
  /** The content preview — a clip's text, a file's name. */
  detail: string;
  /** Which side it came from, which sets the arrow's direction. */
  from: 'phone' | 'mac';
  /** 0–1 for a file in flight; omit for instant events. */
  progress?: number;
};

type Listener = () => void;

let current: (IslandEvent & { id: number }) | null = null;
let nextId = 1;
let hideTimer: ReturnType<typeof setTimeout> | undefined;
const listeners = new Set<Listener>();

function emit() {
  listeners.forEach((l) => l());
}

/** Shows an event on the island, replacing whatever it was showing. */
export function pushIsland(event: IslandEvent, holdMs = 3400) {
  current = { ...event, id: nextId++ };
  emit();
  clearTimeout(hideTimer);
  hideTimer = setTimeout(() => {
    current = null;
    emit();
  }, holdMs);
}

/** Updates the event on screen in place (a file's progress), without restarting its timer. */
export function updateIsland(patch: Partial<IslandEvent>) {
  if (!current) return;
  current = { ...current, ...patch };
  emit();
}

function subscribe(listener: Listener) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function useIsland() {
  return useSyncExternalStore(
    subscribe,
    () => current,
    () => null,
  );
}
