'use client';

import posthog from 'posthog-js';
import { useEffect } from 'react';
import { POSTHOG_KEY } from '@/lib/site';

/** An address without its query or fragment: /reset?token=… must never leave as a token. */
function bare(url: unknown): unknown {
  if (typeof url !== 'string') return url;
  try {
    const u = new URL(url);
    return `${u.origin}${u.pathname}`;
  } catch {
    return url.split(/[?#]/)[0];
  }
}

/**
 * Page views for the website, and nothing else: no cookies or storage (so no consent banner),
 * no autocapture (it can record text on the page), no session recording,
 * no surveys. Every address is sent without its query string or fragment.
 */
export function Analytics() {
  useEffect(() => {
    if (!POSTHOG_KEY || posthog.__loaded) return;
    posthog.init(POSTHOG_KEY, {
      api_host: 'https://us.i.posthog.com',
      // A visitor is a daily-rotating hash PostHog makes on its server, not a stored id. With
      // memory persistence every page load counted as a new visitor, so the numbers were noise.
      // Needs "Cookieless server hash mode" on in the PostHog project, or events are dropped.
      cookieless_mode: 'always',
      person_profiles: 'identified_only',
      autocapture: false,
      capture_pageview: true,
      capture_pageleave: true,
      disable_session_recording: true,
      disable_surveys: true,
      before_send: (event) => {
        if (!event) return event;
        // Only the real site counts; previews and localhost are dev, as the apps' debug builds.
        event.properties.environment =
          window.location.hostname === 'fuseos.theshaik.dev' ? 'production' : 'debug';
        for (const key of ['$current_url', '$referrer', '$initial_referrer'] as const) {
          if (key in event.properties) event.properties[key] = bare(event.properties[key]);
        }
        return event;
      },
    });
  }, []);
  return null;
}
