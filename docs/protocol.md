# FuseOS — LAN Device-to-Device Protocol

**Transport:** direct, encrypted connection over the local network · **Encoding:** Protocol Buffers (`proto/`)

This is the **data plane**: the actual clipboard and file bytes moving **directly between two trusted devices**. It never involves the server or the database. The control plane ([api.md](api.md)) only *introduces* the devices (exchanges LAN addresses and public keys); everything below happens peer-to-peer.

---

## 1. Discovery & connection

1. **Discovery:** `/signal` relays each peer's current `lanAddress` and `publicKey` on the peer card — the address says where to dial, the key says who must answer. That is everything needed to open the channel, so **mDNS (`_fuseos._tcp`) is not implemented yet**; it is the fallback for when pairing has to work without internet, and it is deliberately deferred.
2. **Who dials:** every device listens on an ephemeral TCP port, but only the device with the **lexicographically lower device id** dials. Without that tie-break both ends dial at once and every pair ends up with two half-used connections.
3. **Connect & authenticate:** the dialer opens a plain TCP connection and both sides exchange a handshake frame — `[2-byte BE id length][device id UTF-8][32-byte nonce]` — in the clear. The device id is there because the listening side sees only an IP address and needs to know whose key to look up. Each side then requires the peer's **static P-256 public key** to be one the control plane vouched for ([schema.md](schema.md) `device_trust`); an unknown key closes the socket before anything is decrypted.
4. **Channel keys:** ECDH over the two static keys, salted with both nonces, expanded by HKDF-SHA256 into **one key per direction** (`fuseos:lan:v1:low-to-high` and `…:high-to-low`, ordered by device id so both ends agree without extra negotiation). Every frame after the handshake is `[4-byte BE length][AES-GCM ciphertext || 16-byte tag]` over a serialised `Envelope`, with the frame counter as the GCM nonce.

   This is TLS-shaped rather than literally TLS: the same guarantees (authenticated peers, per-session keys, per-frame integrity) without a certificate chain, because the control plane already distributes the keys that a PKI would otherwise establish.
5. **Maintain:** the channel is persistent and bidirectional; a `Heartbeat` envelope every 15s keeps it alive; loss triggers reconnection with exponential backoff capped at 15s.

> **No forward secrecy.** The ECDH is static-static, so an attacker holding a device's private key can decrypt recorded sessions. The upgrade is ephemeral keys plus signatures (Noise IK); it was skipped because it costs a full handshake protocol to defend against someone who already has the device.

## 2. Message envelope

Every message shares a common header carrying the fields that make sync safe:

```proto
// proto/fuseos.proto (illustrative)
message Envelope {
  string  source_device_id = 1;  // who originated this event
  uint64  seq              = 2;   // monotonic per source device
  int64   sent_at_unix_ms  = 3;
  oneof body {
    ClipText  clip_text  = 10;
    ClipImage clip_image = 11;
    FileMeta  file_meta  = 12;
    FileChunk file_chunk = 13;
    Ack       ack        = 14;
    Heartbeat heartbeat  = 15;
  }
}
```

- **`source_device_id`** + **`seq`** are mandatory on every event. They drive loop prevention and duplicate suppression (§4).
- Tag numbers are **permanent** — add fields, never renumber or reuse. `proto/` is the single source of truth; both clients and the server generate bindings from it.

## 3. Message types

| Type | Direction | Payload |
| --- | --- | --- |
| `CLIP_TEXT` | either | UTF-8 text |
| `CLIP_IMAGE` | either | image bytes + mime (chunked if large, like files) |
| `FILE_META` | sender → receiver | name, size, mime, checksum |
| `FILE_CHUNK` | sender → receiver | ordered chunk index + bytes |
| `ACK` | receiver → sender | acknowledges an applied event / completed transfer |
| `HEARTBEAT` | either | liveness |

## 4. Loop-prevention invariant (critical)

Clipboard sync is a broadcast and would otherwise loop forever. The rule:

1. **Only user-initiated local changes originate a new event.** When a device detects its *own* clipboard changed because the user copied something, it emits an event with its `source_device_id` and the next `seq`.
2. **A device that receives an event applies it but never re-emits it.** Injecting received content into the local clipboard must **not** be treated as a new user copy. (Implementations suppress the self-trigger, e.g. by remembering the last-applied content/hash.)
3. **Duplicate suppression:** a receiver ignores any event whose `(source_device_id, seq)` it has already applied.
4. **Conflict resolution:** last-write-wins by `seq` / `sent_at_unix_ms`.

> This is the single most important rule in the data plane. Weakening any of these four points reintroduces infinite clipboard loops. See also `CLAUDE.md` and [LLD.md](LLD.md) §6.

## 5. Clipboard flow

```
User copies on A
  └─► A emits Envelope{ source=A, seq=n, ClipText }  ──(LAN, encrypted)──►  B
                                                                            │ verify source is trusted
                                                                            │ dedupe (A,n) not seen
                                                                            │ apply to NSPasteboard/ClipboardManager
                                                                            │ (do NOT re-emit)
                                                                            ▼
                                                        B emits Envelope{ Ack } ──► A
```

### 5.1 Platform constraints on clipboard access

Two facts about the host platforms shape what clipboard sync can actually promise. Neither is a bug to engineer around.

**Android only lets the focused app read the clipboard.** Since Android 10 (API 29) a background app gets nothing back; Android 12+ also shows a toast on every read. No permission, foreground service, or manifest flag lifts this — the only escapes are an `AccessibilityService` (Play Store policy risk) or the user explicitly sharing. So:

| Direction | Works when |
| --- | --- |
| macOS → Android (inject) | Always. Writing the clipboard is unrestricted. |
| Android → macOS (auto-capture) | Only while FuseOS is on screen. |
| Android → macOS (background) | Via the Share sheet only. |

This is why **Share-sheet send is not a convenience feature on Android — it is the primary background path out of the device**, and it should land before file transfer.

**`NSPasteboard` has no change notification.** No observer, no delegate, no notification: the only way to detect a copy on macOS is to poll `changeCount`. `ClipboardSync` does so every 300 ms. This is the one sanctioned exception to the project's "never poll" rule (`CLAUDE.md`), which is about network round trips — this is a local integer read with no I/O behind it.

## 6. File transfer flow

1. Sender emits `FILE_META` (name, size, mime, checksum).
2. Sender streams ordered `FILE_CHUNK` messages.
3. Receiver reassembles, verifies the checksum, and offers/saves the file (Storage Access Framework on Android; save panel / Downloads on macOS).
4. Receiver emits `ACK` on success. A failed/interrupted transfer is retried at the transport layer — **never queued on the server**.
5. Images larger than a single message use the same chunking mechanism.

## 7. Security

- **End-to-end encryption** on the channel: AES-256-GCM with keys derived per connection and per direction (§1).
- **Peer authentication** by device public key against `device_trust`, checked before any frame is decrypted.
- **Integrity**: the GCM tag authenticates every frame, and the frame counter is the nonce, so a reordered or replayed frame fails its tag check rather than being applied. File checksums are verified on receipt.
- **No forward secrecy** — see the note in §1.
- Because payloads never touch the server, there is no server-side exposure of clipboard/file content.
- Private keys never leave their device: the macOS login keychain, and Android DataStore (Keystore ECDH needs API 31 and minSdk is 26 — tracked as a `ponytail:` note in `SessionStore.kt`).

## 8. Failure behavior (fail soft)

- A dropped frame or lost peer degrades gracefully: the channel reconnects with backoff; the app never crashes on data-plane errors.
- No indefinite queuing of clipboard events — if a peer is offline, the copy simply isn't delivered (the clipboard is not a durable outbox in v1).
- Heartbeats detect half-open connections and trigger reconnect.
