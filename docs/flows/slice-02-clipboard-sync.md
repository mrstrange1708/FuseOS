# Slice 02 — Clipboard Sync (text)

**Status:** Built, pending verification on two physical devices.
**Goal:** copy on one device, paste on the other, with no loop and no byte of content touching the server.

This slice built the **data plane** that [slice-01](slice-01-device-login.md) stopped short of. Slice 01 got two devices to see each other through the control plane; this one gets them to talk to each other without it.

## What was built

**Protobuf bindings, at last.** `proto/fuseos.proto` had existed since the first commit with nothing generating from it. Android now generates via `protobuf-gradle-plugin`, macOS via `protoc` in `build-app.sh`. There are deliberately no TypeScript bindings — the server never sees a payload, so it has nothing to decode.

**Real device keypairs.** `publicKey` was 32 random bytes on both clients: a stable identifier with no cryptography behind it. It is now a P-256 keypair — macOS in the login keychain, Android in DataStore — travelling as base64 SPKI DER, the one encoding both `PublicKey.getEncoded()` and CryptoKit's `derRepresentation` produce.

**The LAN channel** (`LanTransport` + `LanChannel` + `LanCrypto`, mirrored on both platforms). Each device listens on an ephemeral TCP port and advertises it as `lanAddress` over `/signal`. The lower device id dials. The handshake exchanges ids and nonces in the clear, authenticates the peer's static key against what the control plane vouched for, then derives per-direction AES-GCM keys by ECDH + HKDF. See [protocol.md](../protocol.md) §1.

**Clipboard sync** (`ClipboardSync` + `LoopGuard`). All four loop-prevention rules live in `LoopGuard`, deliberately separated from the platform clipboard APIs so they can be tested without a device.

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
5. Run `tcpdump -i any port 3000` during a copy and confirm **zero payload bytes** reach the server. This is the architecture's central invariant and deserves a direct measurement rather than an assumption.
6. Toggle Wi-Fi off and on; confirm the channel returns within a few seconds.

**A likely environment trap:** many routers enable AP/client isolation, which silently blocks all device-to-device traffic. If step 1 fails, verify a plain `nc` between the two devices before debugging FuseOS.

## Next

Clipboard images (`ClipImage` inline under ~256 KB, `FileMeta`/`FileChunk` above), then share-sheet send, then file transfer.
