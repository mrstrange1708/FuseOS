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
| Error tracking | `src/observability/sentry.ts` | `initSentry()` runs first in `index.ts`; no-op if `SENTRY_DSN` unset. Errors captured in the Fastify error handler. |
| Analytics | `src/observability/analytics.ts` | `capture(distinctId, event, props)` with the payload guard; no-op if `POSTHOG_API_KEY` unset. |
| Config | `src/config/env.ts` | Zod-validated env; both integrations optional in local dev. |

Configuration (see `server/.env.example`): `SENTRY_DSN`, `POSTHOG_API_KEY`, `POSTHOG_HOST`. Absent values disable the integration cleanly, so local dev and CI need no external services.

## Client integration (later)

The Android (PostHog Android + Sentry Android) and macOS (PostHog + Sentry Cocoa) apps will adopt the same rule: capture UX/reliability metadata only — pairing success, sync latency, connection drops, error reports — **never** the synced content. Wire these when the client apps are built.

## Suggested events (metadata only)

`server_started`, `device_registered`, `pairing_initiated`, `pairing_completed`, `pairing_failed`, `peer_connected`, `peer_disconnected`, `clip_synced` (with `sizeBytes`, `kind=text|image`, `latencyMs` — **not** the content), `file_transfer_completed` (`sizeBytes`, `mime`, `durationMs`).
