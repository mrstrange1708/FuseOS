# Slice 02 — Clipboard Sync (text + images)

**Status:** Built, pending verification on two physical devices.
**Goal:** copy on one device, paste on the other, with no loop and no byte of content touching the server.

This slice built the **data plane** that [slice-01](slice-01-device-login.md) stopped short of. Slice 01 got two devices to see each other through the control plane; this one gets them to talk to each other without it.

## What was built

**Protobuf bindings, at last.** `proto/fuseos.proto` had existed since the first commit with nothing generating from it. Android now generates via `protobuf-gradle-plugin`, macOS via `protoc` in `build-app.sh`. There are deliberately no TypeScript bindings — the server never sees a payload, so it has nothing to decode.

**Real device keypairs.** `publicKey` was 32 random bytes on both clients: a stable identifier with no cryptography behind it. It is now a P-256 keypair — macOS in the login keychain, Android in DataStore — travelling as base64 SPKI DER, the one encoding both `PublicKey.getEncoded()` and CryptoKit's `derRepresentation` produce.

**The LAN channel** (`LanTransport` + `LanChannel` + `LanCrypto`, mirrored on both platforms). Each device listens on an ephemeral TCP port and advertises it as `lanAddress` over `/signal`. The lower device id dials. The handshake exchanges ids and nonces in the clear, authenticates the peer's static key against what the control plane vouched for, then derives per-direction AES-GCM keys by ECDH + HKDF. See [protocol.md](../protocol.md) §1.

**Clipboard sync** (`ClipboardSync` + `LoopGuard`), text and images. All four loop-prevention rules live in `LoopGuard`, deliberately separated from the platform clipboard APIs so they can be tested without a device. Images ride inline in a single frame up to 3 MB rather than being chunked — faster on a LAN and far less code, and it covers the screenshot case that matters. Both sides normalise to PNG.

**A visible history.** Sync was invisible: items went straight to the system clipboard with nothing on screen, so "it isn't working" and "it worked and you didn't notice" looked identical. `ClipboardSync` now keeps the last 50 items in a bounded in-memory ring (also capped at 24 MB, since 50 screenshots would otherwise pin 150 MB), each tagged as copied-here or received, and the dashboard renders them under the device list. Tapping one re-copies it, routed through `LoopGuard.recordApplied` so a re-copy isn't rebroadcast as a fresh local copy. Deliberately not persisted — clipboard content stays as ephemeral as the clipboard itself, and the no-payload-on-disk stance matches the no-payload-on-server one.

## What this slice discovered

**Android cannot read the clipboard in the background.** Since API 29 only the focused app may read it. This is not a bug to route around — it makes clipboard sync asymmetric, and it means share-sheet send is the primary background path out of Android rather than a convenience feature. It should be built before file transfer. See [protocol.md](../protocol.md) §5.1.

**macOS has to poll.** `NSPasteboard` exposes no change notification of any kind, so detecting a copy means watching `changeCount` on a 300 ms timer. It is the one sanctioned exception to the never-poll rule.

**mDNS turned out to be unnecessary for now.** `/signal` already relayed `lanAddress`; adding `publicKey` to the same peer card was a one-line server change and removed the entire discovery problem from this slice. Bonjour/NSD is deferred to when pairing must work without internet.

## Verification

Done in-process:
- 3 JVM tests drive the real handshake over a loopback socket — round trip both directions, five consecutive frames (the only thing that catches GCM counter drift), a peer we hold no key for being rejected, and a tampered frame failing its tag check. Confirmed non-vacuous by breaking the counter and watching them fail.
- 9 JVM tests plus 13 Swift assertions pin the loop-prevention rules, including the full two-device round trip that must settle rather than loop.
- Java ↔ CryptoKit interop was verified directly: identical ECDH shared secrets, identical HKDF output, and AES-GCM frames sealed by each side opening on the other.

**Still required, and not yet done — two physical devices on one Wi-Fi network:**
1. Both dashboards show `connected · direct`.
2. Copy text on the phone (with FuseOS on screen), paste on the Mac. Then the reverse.
3. Time the round trip against the p95 < 300 ms target in [PRD.md](../PRD.md) §7.
4. Copy on both devices within the same second — confirm it settles, with no ping-pong.
5. Copy a screenshot each way; confirm it arrives as an image and not as a `content://` URI or a file path.
6. Run `tcpdump -i any port 3000` during a copy and confirm **zero payload bytes** reach the server. This is the architecture's central invariant and deserves a direct measurement rather than an assumption.
7. Toggle Wi-Fi off and on; confirm the channel returns within a few seconds.

**A likely environment trap:** many routers enable AP/client isolation, which silently blocks all device-to-device traffic. If step 1 fails, verify a plain `nc` between the two devices before debugging FuseOS.

## Feedback: the island

Sync is invisible by nature — content simply appears on the other device — which leaves no way to tell "it worked" apart from "it is broken". `ClipIsland.swift` is that signal on macOS: a glass capsule that drops under the notch for 2.6 s on every clip, in either direction, then gets out of the way.

It hangs off `ClipboardSync.onClipEvent`, which fires once per clip from `record` — the single funnel both directions already pass through. Deliberately not `onHistoryChanged`, which also fires on eviction and on sign-out clearing; neither is an event worth showing anyone.

It is an `NSPanel` (`.statusBar` level, `canJoinAllSpaces`, `fullScreenAuxiliary`, non-activating) rather than a SwiftUI window, so it sits above full-screen apps, follows the user across Spaces, and never steals focus from whatever they are typing into. A second clip replaces the first rather than queueing: a backlog of stale animations is noise, and only the newest clip is still true.

## Next

Share-sheet send — promoted ahead of file transfer, because on Android it is the only way to send anything while the app is off screen. Then file transfer, which brings `FileMeta`/`FileChunk` reassembly and with it images above 3 MB.

## History that survives a restart

History was memory-only, so every clip vanished when the app closed — and on Android the OS closes it constantly. `ClipHistoryStore` (both clients) now writes it on every change: text in a JSON index, image bytes in files beside it, because base64-ing a 2 MB screenshot into JSON would triple it and force the whole history to be parsed to read one entry.

**Local storage only.** Clipboard content still never reaches the server or the database — that invariant is about the control plane, and this is the device that already has the content on its own clipboard. Sign-out deletes it; backgrounding does not.

The time filter (24 hours / 7 days / 30 days / All) is a *view* over what is held, not a retention policy: eviction remains the size and count caps in `ClipboardSync`, so narrowing hides nothing permanently.

## Shell

Both clients now have the same five areas, in platform-appropriate furniture:

| | Android | macOS |
| --- | --- | --- |
| Chrome | floating glass bar, raised centre action | sidebar (`NavigationSplitView`) + menu bar extra |
| Areas | Home · Screen · **Send** · History · You | Home · History · Devices · Screen · Account |

Android's centre slot is a verb, not a page — pushing the clipboard is what people open the app to do, and it can read the clipboard precisely because the app is on screen. On macOS the menu bar item carries that weight instead: continuity is reached for mid-task, so the last six clips are one click away without hunting for a window. Closing the window no longer quits the Mac app.

Screen sharing has a slot on both and is locked on both. It is out of scope for v1 (see CLAUDE.md) and would change the transport design; reserving the slot keeps the shape of the app from shifting under people later.
