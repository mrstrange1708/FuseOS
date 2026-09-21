# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What FuseOS is

FuseOS is a cross-device continuity ecosystem for **Android ⇄ macOS**: copy on your phone and paste on your Mac, transfer files both ways, and use the native Share sheet to send content to the other device. One account, same login on both apps. Latency is the product — it must feel instant.

Read `docs/` before writing code. `docs/PRD.md` (what & why), `docs/HLD.md` (architecture), `docs/LLD.md` (implementation detail), `docs/schema.md`, `docs/api.md`, `docs/protocol.md` (the contracts). Both apps and the server are **built and running** — see "Where the build is" at the bottom of this file.

## Architecture in one paragraph (do not violate this)

FuseOS is **hybrid**: a cloud **control plane** and a LAN **data plane**, and they must stay separate.

- **Control plane** = the Node/TypeScript `server/` + PostgreSQL. It handles auth, the device registry, and WebSocket **signaling** (presence + exchanging LAN addresses). This is the only thing that talks to the database.
- **Data plane** = **direct device-to-device over the LAN** (same WiFi). Clipboard content and files travel here, encrypted, peer-to-peer. **This data never passes through `server/` and never touches the database.**

The single most important invariant: **clipboard/file payloads never transit the server or the DB.** If a change would route payload data through the control plane, it is wrong — reconsider it.

## Engineering principles (non-negotiable)

These are the house rules. Hold the line on them in every change and every review.

1. **Latency is the top priority.** Event-driven only — never poll. No unnecessary network hops. The server stays off the clipboard/file hot path (that's LAN-direct). When you touch a sync path, think about the round trip; treat a latency regression as a bug, not a tradeoff.
2. **The database (PostgreSQL) is the source of truth** — but only for identity and the device registry (trust is derived from it: same account = trusted; the manual link code is an in-memory fallback, never a table). It is **never** a store for clipboard or file payloads (those are ephemeral and LAN-only).
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
- `website/` — the public download page, one static HTML file, deployed to GitHub Pages by `.github/workflows/pages.yml`. Downloads point at the `preview` GitHub release's assets (`FuseOS.dmg`, `FuseOS-preview.apk`).
- `docs/` — the design of record. [`docs/testing.md`](docs/testing.md) explains the test strategy: what is verified where, and what only two physical devices can confirm.

The two native apps coordinate **only** through the shared `proto/` contract — that is the seam between them. A protocol change is a cross-cutting change: update `proto/`, then both clients and the docs.

## The loop-prevention invariant

Clipboard sync is a broadcast, so it can loop. The rule (see `docs/protocol.md`): every clipboard/file event carries a `source_device_id` and a monotonic sequence number. A receiving device **applies** the event but **never re-emits** it, and conflicts resolve last-write-wins. Preserve this in any sync code — breaking it causes infinite clipboard loops across devices.

## Scope discipline (v1)

v1 is **foundation only**: auth, device linking, clipboard sync (text + images), file transfer, and Share-sheet send. **Screen mirroring, remote control, and call/SMS relay are explicitly out of scope for v1** — don't build toward them yet; they're a later phase and would change the transport design.

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

**CI** (`.github/workflows/ci.yml`) runs `format:check`, `lint`, `typecheck`, and `test` on every push to `main` and every PR. Run these locally before pushing; they must all pass. `lint`/`format` are root-level (ESLint flat config + Prettier); `typecheck`/`test` fan out to workspaces (`tsc --noEmit`, Vitest).

The native clients are built with their own toolchains, outside PNPM:
- **Android** (`clients/android/`): `./gradlew assembleDebug` to produce a debug APK; `./gradlew test` for unit tests.
- **macOS** (`clients/macos/`): `./build-app.sh` then `open .build/FuseOS.app`; `./make-dmg.sh` for a release `.build/FuseOS.dmg`; `swift test` for the unit tests. SwiftPM, no `.xcodeproj`. Run the bundle rather than `swift run` — LAN connections need local-network permission, which only a bundle identifier can hold.

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
into ten days that end with v1 released and hosted. v2 (mirroring, remote control, call/SMS relay,
cross-network relay) starts only after v1 ships.

| Day | Date | Work | State |
| --- | --- | --- | --- |
| — | Aug | Android one-tap send: QS tile, notification action, `CaptureActivity` | ✅ done (plus the clipboard island and an IME) |
| — | Aug 21 | File transfer core, no UI: `FileTransfer` on both clients, 64 KB chunks, sha-256 verify, `Ack` | ✅ done |
| 1 | Sep 21 | File transfer UI: macOS drop zone + open panel, Android SAF picker, progress, cancel both ways (`FileCancel`), files land in Downloads | ✅ done — needs a two-device run |
| 2 | Sep 22 | Share sheet both ways for files: macOS Share extension target, Android `ACTION_SEND` with a file `Uri` through `Transfers.send` | ⬜ next |
| 3–4 | Sep 23–24 | Real auth: Better Auth on the canonical schema, replacing `server/src/auth/dev-auth.ts` | ⬜ |
| 5 | Sep 25 | Inngest (presence sweep, verification email) + instrument and measure the clipboard hot path | ⬜ |
| 6 | Sep 26 | Hosting: server on an always-on free VM + Neon Postgres + TLS; release builds default to the hosted `https`/`wss` URL | ⬜ |
| 7 | Sep 27 | Release pipeline: signed release APK + DMG (self-signed cert, no notarization) on GitHub Releases | ⬜ |
| 8–9 | Sep 28–29 | Two-device soak against `docs/testing.md`, fix what it finds | ⬜ |
| 10 | Sep 30 | Docs pass, tag v1.0.0 | ⬜ |

Already working: auth (dev stand-in), device linking, presence/`/signal`, clipboard text and
images both ways with history and reboot survival, Android Share-sheet send (text/images), file
transfer both ways with progress and cancel.

Two constraints worth knowing before proposing anything in this area:

- **Android clipboard capture stops at one tap.** Only the focused window may read the
  clipboard (API 29+) and no permission lifts it, so the tile / notification / island route
  through a focused `CaptureActivity`. The default-IME exemption is why `ime/` exists, but a
  keyboard that replaces the user's own is a cost they have rejected for now — it is unused,
  and an AccessibilityService is off the table (Play Store). See `docs/protocol.md` §5.1.
- **File transfer is not resumable.** A dropped link fails the transfer and the user re-sends;
  see `docs/protocol.md` §6.
- **This Mac has no Xcode, and its macOS 27 Command Line Tools are incomplete.** The 27 SDK lacks
  SwiftUI's macro plugin, so the app only builds against the 26.5 SDK:
  `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ./build-app.sh`.
  `swift build --target FuseOSCore` works as-is. XCTest ships only with Xcode, so `swift test`
  cannot run here: install Xcode (free) to run the macOS suite.
