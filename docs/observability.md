# FuseOS — Observability

**Analytics:** PostHog · **Error tracking:** Sentry

FuseOS uses PostHog for product analytics and Sentry for error tracking, across the server and (later) both native clients.

---

## The one hard rule: never send user payloads

Clipboard contents, file bytes, and image data live **only** on the LAN data plane. They must **never** reach PostHog, Sentry, logs, or any third party. This is the same privacy invariant that keeps payloads off the server and out of the database — it extends to observability.

Enforcement in the server:
- `server/src/observability/analytics.ts` exposes `capture()` with a boundary guard (`assertNoPayload`) that **throws** if a property key looks like a payload (`text`, `content`, `clipboard`, `file`, `image`, `data`, …). A careless call fails loudly in dev/CI instead of silently exfiltrating user data. Covered by `analytics.test.ts`.
- Only **operational metadata** is ever captured — event name, device platform, sizes/counts, latency, success/failure. Never the content itself.
- Sentry: scrub/deny-list any payload-bearing fields; do not attach clipboard/file contents to breadcrumbs or extra context.

## Server integration

| Concern | Module | Behavior |
| --- | --- | --- |
| Error tracking | `src/observability/sentry.ts` | `initSentry()` runs first in `index.ts`; no-op if `SENTRY_DSN` unset (project `server` in `fuseos-y2`). Errors captured in the Fastify error handler and failed Inngest runs. Errors only, no traces; `scrub()` keeps the route and drops query strings, bodies, headers and cookies (verify and reset links carry tokens). |
| Analytics | `src/observability/analytics.ts` | `capture(distinctId, event, props)` with the payload guard; no-op if `POSTHOG_API_KEY` unset. |
| Config | `src/config/env.ts` | Zod-validated env; both integrations optional in local dev. |

Configuration (see `server/.env.example`): `SENTRY_DSN`, `POSTHOG_API_KEY`, `POSTHOG_HOST`. Absent values disable the integration cleanly, so local dev and CI need no external services.

## Client integration

**Sentry is wired in both apps** (organisation `fuseos-y2`, projects `android` and `macos`), with every channel that could carry content turned off:

| | Android (`FuseApp.kt`, `io.sentry:sentry-android`) | macOS (`AppDelegate.startSentry`, `sentry-cocoa`, linked statically) |
| --- | --- | --- |
| Personal data (IP, user) | off (`isSendDefaultPii = false`) | off (`sendDefaultPii = false`) |
| Screenshots / view hierarchy | off | not collected on macOS |
| Tap breadcrumbs / UI tracing | off — a tapped Compose node can carry its text | — |
| Performance traces | — | off (`tracesSampleRate = 0`) |
| Environment | `debug` / `production` by build type | `debug` / `production` by build config |

What arrives is the stack trace, the device model and OS, and the app version. The DSNs ship in the apps (a client DSN can only send events); `-PsentryDsn=` (Android) and `FuseSentryDSN` in Info.plist (macOS) override them, and an empty value turns reporting off. Sentry's own Android auto-init is disabled so only ours runs. Release builds are not minified, so stack traces are readable without uploading mappings.

**PostHog** (US cloud, project 636967) is on for the server, the website and both apps. Everyone is named by account id, so a person counts once across phone, Mac and web — the apps learn it from `POST /devices` (`userId`), which they call on every launch, and `reset()` on sign-out.

- **Server events** (distinct id = the account's random id, never an email): `server_started`, `signed_up` / `signed_in` (`method: email|google`), `email_verified`, `device_registered` (`platform`, `new`), `password_reset_requested` (anonymous — the answer must not depend on whether the account exists). Off under test (`NODE_ENV=test`), so the suite's throwaway accounts never reach the project.
- **Apps** (`Usage.kt` + posthog-android; `FuseOSCore/Usage.swift` + `Analytics.swift` + posthog-ios): `Application Opened` / `Backgrounded` / `Installed` / `Updated` (daily actives), and one `feature_used` per feature, named in a single place — the LAN channel's `send` — from the message type alone: `clipboard_text`, `clipboard_image` (`sizeBytes`), `file_transfer` (`sizeBytes`), `screen_mirroring` (`remoteControl`), `sidecar`, `ring_phone`, `open_link`, `now_playing`, `trackpad`, `remote_control`, `notifications`, `notification_reply`, `notification_open`, `call` (`action`), `unlock`. Counted by the sending device, so nothing counts twice; continuous ones (trackpad, notifications, now playing, remote control) count once per 10 minutes. A super property `environment` (`debug`/`production`) separates dev builds. No screen views, deep links, autocapture or session replay. Location is PostHog's GeoIP (city/country) from the device's IP. The **Usage statistics** switch (Mac: Account → Everyday; Android: You → Account) is PostHog's opt-out, which it remembers. The project key ships in the apps like the DSNs; `-PposthogKey=` / `FusePostHogKey` override it, empty turns it off.
- **Website** (`website/src/components/analytics.tsx`, posthog-js): page views and page leaves only — memory persistence (no cookies or storage, so no consent banner), no autocapture (it can record text), no session recording, no surveys, and `before_send` strips the query and fragment from every address, so `/reset?token=…` never leaves as a token.

## Suggested events (metadata only)

`server_started`, `device_registered`, `peer_connected`, `peer_disconnected`, `clip_synced` (with `sizeBytes`, `kind=text|image`, `latencyMs` — **not** the content), `file_transfer_completed` (`sizeBytes`, `mime`, `durationMs`).
