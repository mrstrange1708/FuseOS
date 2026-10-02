# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What FuseOS is

FuseOS is a cross-device continuity ecosystem for **Android ⇄ macOS**: copy on your phone and paste on your Mac, transfer files both ways, and use the native Share sheet to send content to the other device. One account, same login on both apps. Latency is the product — it must feel instant.

Read `docs/` before writing code. `docs/PRD.md` (what & why), `docs/HLD.md` (architecture), `docs/LLD.md` (implementation detail), `docs/schema.md`, `docs/api.md`, `docs/protocol.md` (the contracts). Both apps and the server are **built and running** — see "Where the build is" at the bottom of this file.

## Architecture in one paragraph (do not violate this)

FuseOS is **hybrid**: a cloud **control plane** and a LAN **data plane**, and they must stay separate.

- **Control plane** = the Node/TypeScript `server/` + PostgreSQL. It handles auth, the device registry, and WebSocket **signaling** (presence + exchanging LAN addresses). This is the only thing that talks to the database.
- **Data plane** = **direct device-to-device over the LAN** (same WiFi). Clipboard content and files travel here, encrypted, peer-to-peer. **This data never touches the database, and the server never sees it in the clear.**

The single most important invariant: **the server never reads a payload, and nothing stores one.** Since 2026-10-01 (the user's call, after college Wi-Fi isolated the devices) there is one exception to "never transits the server": the **relay** (`docs/protocol.md` §19). When the LAN can't link two devices, their *sealed* channel — end-to-end encrypted with keys only the two devices hold — runs over `/signal`, and the server forwards bytes it cannot decrypt, never parsing, storing or logging them. It is a fallback only (the LAN always wins), carries small things only (never files, mirroring or Sidecar), and is rate-limited. Anything else that would route payload data through the control plane — or let the server read one — is wrong; reconsider it.

## Engineering principles (non-negotiable)

These are the house rules. Hold the line on them in every change and every review.

1. **Latency is the top priority.** Event-driven only — never poll. No unnecessary network hops. The server stays off the clipboard/file hot path (that's LAN-direct). When you touch a sync path, think about the round trip; treat a latency regression as a bug, not a tradeoff.
2. **The database (PostgreSQL) is the source of truth** — but only for identity and the device registry. Trust starts from it — only the account's devices can link — but **each device also keeps its own allow-list** (`DeviceTrust`, `docs/protocol.md` §3): a device that joins later links only after the user taps Allow on an existing one, so a stolen password (or a compromised server) cannot quietly add a device. The manual link code is an in-memory fallback, never a table. It is **never** a store for clipboard or file payloads (those are ephemeral and LAN-only).
3. **Never let bad data into the DB.** Integrity is enforced in three layers, all required: (a) the schema itself — NOT NULL, FK, UNIQUE, CHECK, via Drizzle; (b) Zod validation at every external boundary before anything reaches a query; (c) transactions around any multi-row write. Don't rely on application logic alone for an invariant a constraint can guarantee.
4. **Minimize schema migrations.** Design the schema deliberately up front. Prefer additive, backward-compatible changes. Avoid destructive migrations; a rename/drop needs a real reason.
5. **Durable async work goes through Inngest.** Anything that must not be silently lost (presence-timeout sweeps, email verification) is an Inngest function, not fire-and-forget.
6. **Observability never sees user payloads.** PostHog (analytics) and Sentry (errors) receive only operational metadata — event names, platform, sizes, latency. Clipboard/file **contents never** reach analytics, error reports, or logs. The `capture()` guard in `server/src/observability/analytics.ts` enforces this and will throw on a payload-like property. See `docs/observability.md`.

## Repo layout & tooling

Monorepo managed with **PNPM workspaces + Turborepo** on **Node 22** (see `.node-version`). PNPM's strict `node_modules` is deliberate — it prevents phantom dependencies. Use `pnpm`, not `npm`/`yarn`.

- `server/` — Node 22 + TypeScript + Fastify control plane; `ws` for the `/signal` WebSocket. A PNPM workspace.
- `packages/proto/` — shared **protobuf** wire-contract source and its generated TypeScript. A PNPM workspace.
- `proto/` — the `.proto` source of truth for the device-to-device protocol. Every platform generates its own bindings from these files; when the wire format changes, it changes here first.
- `clients/android/` — Kotlin + Jetpack Compose (Gradle toolchain; **outside** the PNPM workspace).
- `clients/macos/` — SwiftPM (**outside** the PNPM workspace). Split into `FuseOSCore` (logic: crypto, LAN transport, clipboard rules — unit-tested) and `FuseOS` (the SwiftUI app). An executable target cannot be imported by tests, which is why the logic lives in its own library.
- `website/` — the public download page: Next.js (static export) + Tailwind 4, Aceternity UI components (copied into `src/components/ui/`, recoloured to the ember palette), GSAP ScrollTrigger/SplitText/DrawSVG and Motion. Deployed by Vercel (from `main`; each PR gets a preview); `pnpm website` or the `website` mprocs pane runs it on :3100. Its Dynamic Island lives in the notch section (`src/components/sections/notch.tsx`, a pinned scroll that zooms into a MacBook notch and steps the island through clipboard → image → file → share → linked) and also reads `src/lib/island.ts` — call `pushIsland()` to show an event; that is the hook for wiring real FuseOS events in later. Download buttons go to `/download/mac` and `/download/android`, which `website/vercel.json` redirects to the latest GitHub release's `FuseOS.dmg` / `FuseOS.apk` (built and signed by `release.yml`; binaries stay out of git and Vercel). A PNPM workspace.
- `docs/` — the design of record. [`docs/testing.md`](docs/testing.md) explains the test strategy: what is verified where, and what only two physical devices can confirm.

The two native apps coordinate **only** through the shared `proto/` contract — that is the seam between them. A protocol change is a cross-cutting change: update `proto/`, then both clients and the docs.

## The loop-prevention invariant

Clipboard sync is a broadcast, so it can loop. The rule (see `docs/protocol.md`): every clipboard/file event carries a `source_device_id` and a monotonic sequence number. A receiving device **applies** the event but **never re-emits** it, and conflicts resolve last-write-wins. Preserve this in any sync code — breaking it causes infinite clipboard loops across devices.

## Scope discipline (v1)

v1 is auth, device linking, clipboard sync (text + images, with history catch-up), file transfer, Share-sheet send, and — pulled into v1 by the user on 2026-09-26 — notification sync and **view-only** screen mirroring, both phone → Mac over the existing LAN channel (`docs/protocol.md` §9–§11). On 2026-09-26 the user also chose **free distribution only** — an APK on GitHub Releases, never Google Play, and no paid Apple account — so Play Store policy no longer rules anything out: remote control of the phone from the Mac (an AccessibilityService, `docs/protocol.md` §11) is in, and the continuity features listed in "Where the build is" are being built one feature branch at a time. Anything that needs a paid Apple Team ID (Share extension, notarization, camera/system extensions) stays out.

## Commands

All JS/TS commands run from the repo root via Turborepo (they fan out to the workspaces). Use `pnpm`, never `npm`/`yarn`.

| Task | Command |
| --- | --- |
| Install deps | `pnpm install` |
| Run everything in dev | `pnpm dev` |
| Build all workspaces | `pnpm build` |
| Lint / typecheck / test all | `pnpm lint` · `pnpm typecheck` · `pnpm test` |
| Format (write / check) | `pnpm format` · `pnpm format:check` |
| Regenerate protobuf bindings | no-op — see below |
| Generate a Drizzle migration | `pnpm db:generate` |
| Apply migrations | `pnpm db:migrate` |
| Work in one workspace only | `pnpm --filter server <script>` |
| Run a single server test | `pnpm --filter server test -- <path-or-name>` |

**CI** (`.github/workflows/ci.yml`) runs `format:check`, `lint`, `typecheck`, and `test` on every push to `main` and every PR. Run these locally before pushing; they must all pass. `lint`/`format` are root-level (ESLint flat config + Prettier); `typecheck`/`test` fan out to workspaces (`tsc --noEmit`, Vitest). Two more jobs build the native apps and run their unit tests: Android (`./gradlew testDebugUnitTest assembleDebug`) and macOS (`swift build` + `swift test` on macos-15 with its newest Xcode).

The native clients are built with their own toolchains, outside PNPM:
- **Android** (`clients/android/`): `./gradlew assembleDebug` to produce a debug APK; `./gradlew test` for unit tests.
- **macOS** (`clients/macos/`): `./build-app.sh` then `open .build/FuseOS.app`; `./make-dmg.sh` for a release `.build/FuseOS.dmg`; `swift test` for the unit tests. SwiftPM, no `.xcodeproj`. Run the bundle rather than `swift run` — LAN connections need local-network permission, which only a bundle identifier can hold. The build signs with a self-signed identity it makes once in `~/.fuseos/signing.keychain-db`, so Accessibility, Bluetooth and local-network grants survive rebuilds (an ad-hoc signature voided them silently every build).

> `packages/proto/` is deliberately a stub — the server never decodes a payload, so there are no TypeScript bindings and `pnpm proto:gen` is a no-op.

## Conventions

- **TypeScript (`server/`, `packages/*`)**: `strict` mode on; no `any` without a written reason. Validate all external input with **Zod** at the boundary, then work with typed data internally. Database access goes through **Drizzle** — no raw SQL strings for normal queries. Keep the HTTP/WebSocket layer (Fastify) thin; put logic in services.
- **Errors**: fail loud at the control plane (return a typed error response); fail soft on the data plane (a dropped LAN packet should degrade gracefully and reconnect, never crash the app).
- **Protobuf**: `proto/` is the source of truth for the wire format. Never hand-edit generated bindings. A field is added, never renumbered or reused — protobuf tag numbers are permanent. **Each client generates its own bindings during its own build** — Android via `protobuf-gradle-plugin` (into `app/build/`), macOS via `protoc` in `build-app.sh` (into `Sources/FuseOSCore/Generated/`, gitignored). Both read `proto/` directly, so there is no generation step to run by hand and `pnpm proto:gen` is a no-op. There are deliberately **no TypeScript bindings**: the server never sees a payload, so it has nothing to decode. macOS needs `brew install protobuf swift-protobuf`.
- **Kotlin / Swift**: follow the platform-idiomatic style (Kotlin official style; Swift API Design Guidelines). Match the surrounding code.

## Common workflows

- **Changing the device-to-device wire format**: edit `proto/` first → rebuild both clients (each regenerates its own bindings) → update the Android and macOS code to match → update `docs/protocol.md`. It's a cross-cutting change by nature. The server is not involved; it never sees the data plane.
- **Adding a control-plane endpoint or table**: update `docs/schema.md`/`docs/api.md`, add the Drizzle schema (with constraints), generate a migration (`pnpm db:generate`), add the Zod-validated Fastify route. Keep the docs and the code in step.
- **Adding durable async work**: model it as an Inngest function — don't hand-roll a queue or a `setTimeout`.

## Docs are part of the change

The `docs/` specs and the code must not drift. If you change behavior, update the matching doc in the same change; if a doc and the code disagree, that's a bug to surface, not a discrepancy to quietly pick a side on.

## Where the build is

**Keep this section current.** It is the only place the plan survives between sessions — a
session that ends mid-plan leaves nothing else behind. When a day lands, tick it here in the
same commit as the work, and add what the next session needs to know.

v1 is being finished against a plan agreed on 2026-08-20 (days 1–2) and replanned on 2026-09-21
into ten days that end with v1 released and hosted. On 2026-09-26/27 the user widened v1 into a
continuity suite (below) and set **free distribution only**; hosting, release and the soak slip —
replan them with the user. Work lands **one feature branch per feature**, merged by PR when done.
The encrypted relay (`docs/protocol.md` §19) is built (2026-10-01/02). Still not built: a full Messages pane (reading SMS threads and starting new
ones — replies to SMS already work through notifications). The Mac cannot unlock the phone —
Android allows no app past its lock; unlocking the Mac only wakes the phone's screen.

| Day | Date | Work | State |
| --- | --- | --- | --- |
| — | Aug | Android one-tap send: QS tile, notification action, `CaptureActivity` | ✅ done (plus the clipboard island and an IME) |
| — | Aug 21 | File transfer core, no UI: `FileTransfer` on both clients, 64 KB chunks, sha-256 verify, `Ack` | ✅ done |
| 1 | Sep 21 | File transfer UI: macOS drop zone + open panel, Android SAF picker, progress, cancel both ways (`FileCancel`), files land in Downloads | ✅ done — needs a two-device run |
| 2 | Sep 22 | Share for files both ways: Android `ACTION_SEND`/`SEND_MULTIPLE` of any type (done); Mac via Finder Services + drop on the menu bar item — a real Share extension needs a sandbox + App Group signed with a paid Team ID | ✅ done 2026-09-22 — needs a two-device run |
| — | Sep 26 | Pulled forward by the user: Mac glass redesign (floating nav, link hero, Dock reopen + "Show in Dock", "Ask before sending copies"), Android glass redesign, stale device records hidden, history catch-up (`HistorySync`), notification sync, view-only screen mirroring with rotation (`docs/protocol.md` §9–§11) | ✅ done — needs a two-device run |
| 3–4 | Sep 23–24 | Real auth: Better Auth on the canonical schema, replacing the dev stand-in | ✅ done 2026-09-26 — bearer session tokens (90 days, rolling), dev accounts migrated with their ids and passwords (0003), dev tables dropped (0004), both clients return to sign-in on a 401 |
| 5 | Sep 25 | Inngest (presence sweep, verification email) + instrument and measure the clipboard hot path | ✅ measuring 2026-09-26; Inngest 2026-09-29 (branch `feat/inngest`): presence sweep, verification + welcome + new-device emails through Resend, run end to end locally. Hosted: Inngest Cloud keys and the Resend key are in the gitignored `deploy/server.env`; Resend sends only to the account owner until the domain is verified |
| — | Sep 26–27 | Continuity suite, PRs #4–#13: FuseOS keyboard fixed + clipboard strip; remote control of the phone from the Mac (AccessibilityService); ring the phone, Continuity Camera (removed 2026-09-28), Handoff for links; Now Playing; phone as trackpad/keyboard; answer calls + reply to notifications from the Mac; lock the Mac when the phone leaves; live activities; live menu bar (spark per crossing); Sidecar (phone as a second display). Remove stale devices, server sign-out, Keychain token, sync-speed p95, 16 KB-aligned libraries. `docs/protocol.md` §9–§16 | ✅ merged — none run on two devices yet |
| — | Sep 27 | Round two, PRs #15–#20: copy pop-up with Gboard (FuseOS keyboard removed, quiet notification, dev phone over Wi-Fi); island shows every notification with Reply, hover the notch for recent copies, wide Home; trackpad three-finger swipes + typing; charging both ways (`DeviceStatus`); home-screen widget; Bluetooth-distance lock and experimental phone-unlocks-Mac (`docs/protocol.md` §15, §17) | ✅ merged — none run on two devices yet |
| — | Sep 27 | PRs #22–#23: unlock-with-phone fixed (stable self-signed signature so grants survive rebuilds, per-key typing, `UNLOCKED` held until the link returns); the link spark driven by real events on both apps (comet per clip, beads while a file moves), the website's glow on the link hero, popover trimmed to a glance, website mockups redrawn to match | ✅ merged — needs a two-device run |
| — | Sep 27 | Audit, PRs #25–#26: every send path says "not linked" instead of pretending (Mac island, Android `SendOutcome`); CI now builds both native apps and runs their unit tests (the macOS suite ran for the first time — 142/142 after fixing isolation that overwrote the real clip history); listener continuation race; unlock re-checks the lock before typing; auth rate limit always on; widget goes offline with the service. Website: Continuity section for the whole suite | ✅ merged. Open: require the three CI checks on `main` (repo settings), release pipeline, hosting |
| — | Sep 29 | Device test pass (clipboard text + image, share, files both ways, notifications all ✅ on two devices); sync p95 fixed — it timed a dozing phone and queues behind images (`RoundTrip`, `docs/protocol.md` §4), branch `fix/sync-latency`; **Sign in with Google** on both apps (`/auth/google`, Google Cloud project `fuseos-510109`, `docs/api.md`), branch `feat/google-sign-in` on top of it; then (branch `feat/one-time-codes`) a phone OTP shows in the Mac island as **Copy** / **Paste** (`docs/protocol.md` §10), and the charging emoji became real battery icons | 🟡 built — Google sign-in needs a run on both devices; mirroring, Sidecar, trackpad, ring, calls, Now Playing, away-lock, unlock still need the user's hands |
| — | Sep 30 | Domain `theshaik.dev` on Cloudflare (the user's portfolio is the apex): website `fuseos.theshaik.dev` (Vercel), server to be `fuseos-api.theshaik.dev` (one level deep, so Cloudflare's free cert covers it; DNS only). Resend verified for `fuseos.theshaik.dev` (SPF/DKIM + DMARC), sender `noreply@fuseos.theshaik.dev`. Branch `feat/account-emails`: branded HTML emails (verify, welcome, new device, reset, release), **password reset** (server page + "Forgot password?" on both apps, every session revoked), **release emails** (a `v*` tag → Inngest → Resend Broadcast to the release segment), `/download/*` redirects | ✅ merged (#45) — segment + full-access key set |
| — | Sep 30 | PRs #46–#49: website pages (`/download`, `/help`, `/privacy`, `/terms`, `/reset`, `/verified`, `/report`, 404); Sentry in both apps (errors only); PostHog on the server and website (counts, never content); **Report a bug** form → `POST /feedback` → Inngest → email to `FEEDBACK_TO`. Cloudflare Email Routing: `fuseos@theshaik.dev` forwards to the owner's Gmail (MX/SPF/DKIM on the apex) | ✅ merged — `/reset`, `/report` and sign-in need the hosted server. Open: server Sentry DSN, Google OAuth branding → Publish, rotate keys pasted in chat |
| 6 | Oct 1 | Hosting | ✅ **live 2026-10-01** at `https://fuseos-api.theshaik.dev`: AWS EC2 `t3.micro` (Ubuntu 26.04, 2 GB swap, unattended upgrades) in **Sydney** — the account's "new AWS experience" is locked to `ap-southeast-2`; $100 credits, ~$13/month, a $15 budget alert. Elastic IP `13.236.155.188`, Cloudflare A record **DNS only**. `deploy/compose.yaml` (server + Caddy, Let's Encrypt). SSH: `ssh -i ~/.ssh/fuseos.pem ubuntu@13.236.155.188`; deploy from the dev Mac with **`pnpm deploy:server`** (`deploy/deploy.sh`: migrate prod, copy `deploy/server.env`, check out `origin/main` on the box, rebuild, wait for `/health`) — manual by choice, no CD: SSH stays open to the owner's IP only. Prod DB = Neon `ep-royal-mouse` (**Singapore**, emptied 2026-09-30, migrated to 0005); the laptop stays on `ep-old-snow`. Run `DATABASE_URL=<prod> pnpm db:migrate` before deploying a schema change. Inngest Cloud synced (`PUT /api/inngest`); repo variable `FUSE_SERVER_URL` set. Verified: health + TLS, DB sign-in path, `/signal` through Caddy, a report emailed via Inngest → Resend |
| 7 | Sep 27 | Release pipeline: signed release APK + DMG (self-signed cert, no notarization) on GitHub Releases | ✅ built 2026-09-27 — push a `v*` tag: `.github/workflows/release.yml` builds, signs (keystore + "FuseOS Local Signing" identity in repo secrets; originals in `~/.fuseos/release/` on the dev Mac — back them up, every release must use them), and publishes `FuseOS.apk` / `FuseOS.dmg`; the website downloads `releases/latest`. First run waits on `FUSE_SERVER_URL` |
| 8–9 | Sep 28–29 | Two-device soak against `docs/testing.md`, fix what it finds | ⬜ |
| 10 | Sep 30 | Docs pass, tag v1.0.0 | ⬜ |

Already working (built; the two-device run is still owed): auth (Better Auth), device linking and
removal, presence, clipboard text and images both ways with history catch-up, Share sheet, file
transfer, notifications (with replies and live activities), calls, screen mirroring with remote
control, Sidecar, the phone as trackpad, Now Playing, ring / links, and away-lock. Both
apps have a debug demo mode for design review (`FUSE_DEMO=<dir>` on macOS, `--ez fuse_demo true`
on Android).

Two constraints worth knowing before proposing anything in this area:

- **Android clipboard capture needs a moment of focus.** Only the focused window (or the default
  keyboard) may read the clipboard (API 29+). FuseOS no longer ships a keyboard — people keep
  Gboard. Instead its accessibility service notices the *moment* of copying (a Copy tap or a
  "Copied" confirmation) and opens the invisible `CaptureActivity`, which may read it, and the
  island offers the copy. See `docs/protocol.md` §5.2.
- **File transfer is not resumable.** A dropped link fails the transfer and the user re-sends;
  see `docs/protocol.md` §6.
- **This Mac has no Xcode, and its macOS 27 Command Line Tools are incomplete.** The 27 SDK lacks
  SwiftUI's macro plugin, so the app only builds against the 26.5 SDK:
  `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ./build-app.sh`.
  `swift build --target FuseOSCore` works as-is. XCTest ships only with Xcode, so `swift test` runs in CI (macos-15) — locally it
  cannot run here: install Xcode (free) to run the macOS suite.
