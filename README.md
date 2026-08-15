# FuseOS

**Cross-device continuity for Android and macOS.** Copy on your phone, paste on your Mac. Send files and shared content between your devices in a tap. Low latency, same WiFi, one account.

FuseOS brings Apple-ecosystem-style continuity to the **Android ⇄ macOS** pairing that has never had it.

---

## Why

Modern work spans a phone and a laptop, but an Android phone and a Mac live in separate worlds. Moving a link, a snippet, a screenshot, or a file between them means emailing yourself or piping it through a chat app. FuseOS removes that friction: your devices behave like one system.

## What it does (v1)

- **Clipboard sync** — copy text or an image on one device, it's on the clipboard of the other.
- **File transfer** — send files both ways, Mac ⇄ phone.
- **Share-sheet send** — "Send to my Mac / my phone" from the native share menu.
- **Secure pairing** — link 2–3 of your own devices under one account.

**Deferred to later phases:** screen mirroring, remote control, and phone-call / SMS relay.

## How it works

FuseOS is **hybrid** by design:

- A small cloud **control plane** (`server/` + PostgreSQL) handles login, the device registry, pairing, and real-time **signaling** — helping your devices find each other.
- The actual **clipboard and file data travels directly device-to-device over your local network** — it never passes through the server. That keeps it fast and private.

```
 Android ──┐        control plane (auth, pairing, signaling)        ┌── macOS
           ├──────────────────►  server + PostgreSQL  ◄─────────────┤
           │                                                        │
           └───────────  direct LAN data plane (clipboard/files)  ──┘
                         payloads never touch the server
```

## Run it

```bash
pnpm install
pnpm start            # every service in one mprocs screen
```

`pnpm start` runs [mprocs](https://github.com/pvolok/mprocs) against
[`mprocs.yaml`](mprocs.yaml) — one pane per service, each one live and restartable:

| Pane | What it does |
| --- | --- |
| `server` | Control plane on `:3000`, hot-reloading. |
| `mac` | Builds `FuseOS.app` and launches it. |
| `android` | Waits for a USB phone, then installs and launches the app with this Mac's current LAN IP baked in — so the phone finds the server without editing any file. |
| `logcat` | Phone-side logs. Off by default; press `s` to start it. |

Keys: `j`/`k` switch pane, `s` start/stop, `r` restart, `q` quit everything. The phone
must be on the same Wi-Fi as the Mac.

Prereqs: Node 22 + PNPM, `brew install mprocs`, `server/.env` (copy
`server/.env.example`), Xcode toolchain plus `brew install protobuf swift-protobuf` for
the Mac app, and JDK 17 + Android SDK with `adb` on `PATH` for the phone.

See [`docs/`](docs/) for the full design: [PRD](docs/PRD.md) · [HLD](docs/HLD.md) · [LLD](docs/LLD.md) · [schema](docs/schema.md) · [API](docs/api.md) · [protocol](docs/protocol.md).

## Tech stack

| Layer | Choice |
| --- | --- |
| Monorepo | PNPM workspaces + Turborepo, Node 22 |
| Server | Node 22 + TypeScript + Fastify, `ws` for signaling |
| Database | PostgreSQL + Drizzle ORM |
| Durable jobs | Inngest |
| Auth | Better Auth (self-hosted, JWT) |
| Analytics | PostHog |
| Error tracking | Sentry |
| Android | Kotlin + Jetpack Compose |
| macOS | SwiftUI |
| Wire format | Protocol Buffers (`proto/`) |
| Quality | ESLint · Prettier · TypeScript · Vitest |
| CI | GitHub Actions (`.github/workflows/ci.yml`) |

## Repository layout

```
FuseOS/
├── docs/                 # design of record (start here)
├── server/               # Node/TS control plane
├── packages/proto/       # shared protobuf bindings (generated)
├── proto/                # .proto wire-contract source of truth
└── clients/
    ├── android/          # Kotlin + Jetpack Compose
    └── macos/            # SwiftUI
```

## Status

**Design phase.** The specifications in `docs/` are complete; the applications are being built against them. See [`CLAUDE.md`](CLAUDE.md) for engineering principles and contributor guidance.

## License

See [LICENSE](LICENSE).
