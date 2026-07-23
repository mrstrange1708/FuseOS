# FuseOS — Testing Strategy

How this system is verified, why it is split the way it is, and what deliberately cannot be verified automatically.

FuseOS is unusually hostile to testing: the product is two physical devices talking directly to each other over a network, using platform APIs (clipboard, keychain, pasteboard) that only exist on-device, in two languages that must agree byte-for-byte. The strategy below exists to push as much of that as possible down to something that runs in milliseconds on one machine.

---

## The layers

| Layer | Where | Runs in | Catches |
| --- | --- | --- | --- |
| Pure logic | `LoopGuard`, `LanCrypto` | ms, no I/O | rule and algorithm errors |
| Loopback integration | `LanChannel` over a real socket | ms, localhost | framing, handshake, counter drift |
| Bridge integration | `ClipboardSync` on a private pasteboard | ms, real AppKit | platform wiring that bypasses a rule |
| HTTP + WebSocket | `server/` via a real listener | seconds, real Postgres | contract and authorization errors |
| Cross-platform vectors | frozen bytes in both languages | ms | the two clients silently diverging |
| On-device | two machines, one Wi-Fi | manual | everything else |

The rule of thumb: **if a failure would be silent, it gets a test.** Loud failures (a nil deref, a 500) surface on their own. Silent ones — a clipboard loop, a key derivation mismatch, a peer that just never connects — are what these tests exist for.

## Why the logic is separated from the platform

Both clients keep their rules in a plain object with no platform dependencies:

- **`LoopGuard`** holds all four loop-prevention rules ([protocol.md](protocol.md) §4). It knows nothing about clipboards.
- **`LanCrypto`** holds key derivation and frame sealing. It knows nothing about sockets.

That separation is not tidiness, it is what makes the rules testable at all. `ClipboardManager` and `NSPasteboard` cannot be instantiated in a unit test; the rules they enforce must not be trapped behind them.

On macOS this is enforced by the package layout: `FuseOSCore` (logic) and `FuseOS` (SwiftUI app) are separate targets, because **SwiftPM cannot import an executable target from a test target**. The split was a prerequisite for having macOS tests at all, not an aesthetic choice.

Android keeps the same shape — `net/` and `clipboard/` are plain JVM code, testable without Robolectric or a device — though the module boundary is by package rather than by Gradle module.

## Cross-platform agreement

Two implementations of one protocol drift silently. Three mechanisms guard against it:

1. **Mirrored test cases.** `LoopGuardTest.kt` and `LoopGuardTests.swift` cover the same scenarios deliberately. If one platform's behaviour changes, the pair stops matching and a reviewer can see it.
2. **Frozen wire vectors.** A fixed key, counter, and plaintext produce a byte string pinned in both suites. These were produced by running `javax.crypto` and CryptoKit *independently* and confirming they agreed — so they pin real interoperability rather than recording whatever one platform emits. Changing the GCM nonce layout or the `ciphertext||tag` ordering fails a test instead of silently breaking every connection.
3. **Direct interop runs.** ECDH shared secrets, HKDF output, and AES-GCM frames were verified to match across Java and CryptoKit before the transport was built on top of them.

If a wire-format change is intended, **both** vectors move in the same commit. That is the whole signal.

## Tests must be able to fail

A test that cannot fail is worse than no test: it costs the same to run and buys false confidence. Non-trivial suites here are mutation-checked — the production code is deliberately broken, the suite is confirmed red, and the change is reverted. Two done so far:

- removing the frame-counter increment in `LanChannel` → the multi-frame round trip fails
- collapsing the per-direction key split in `LanCrypto` → 5 tests fail, including the loopback handshake

Where a suite has been mutation-checked, say so in the commit message.

## What the tests are not allowed to do

- **Never weaken production code to make a test pass.** A test that needs a `public` or an injected seam is fine; one that needs the rule relaxed is reporting a real defect.
- **Never leave rows behind.** The server suite runs against a shared Postgres instance. It once left 20+ orphaned device rows, which then showed up as phantom devices in the app. Tests clean up after themselves.
- **Never touch the developer's machine state.** `ClipboardSyncTests` uses a uniquely-named `NSPasteboard`, not `.general`. The keychain checks delete what they create.

## What cannot be tested here, and why

Some things are only real on hardware. These are listed in [flows/slice-02-clipboard-sync.md](flows/slice-02-clipboard-sync.md) as an explicit manual checklist, not left implicit:

- **Local-network permission** (macOS 15+) — a prompt tied to a signed bundle identity.
- **Android's background clipboard restriction** — only the focused app may read; there is no way to observe the restriction from a unit test.
- **Real latency** against the p95 < 300 ms target. Loopback says nothing about Wi-Fi.
- **The central invariant** — that no payload byte reaches the server. Verified by running `tcpdump` during a copy, because it is an architectural claim and deserves a direct measurement rather than an assumption.
- **Router AP/client isolation**, which silently blocks device-to-device traffic on many networks and is the first thing to check when nothing connects.

## Running everything

```bash
pnpm lint && pnpm typecheck && pnpm test     # root: server + workspaces
cd clients/android && ./gradlew testDebugUnitTest
cd clients/macos   && swift test
```

CI runs the first line only; the native suites need their own toolchains. Always confirm Android tests actually *ran* — `app/build/test-results/testDebugUnitTest/*.xml` reports `tests=` and `skipped=`, and a suite that silently skips looks identical to one that passes.
