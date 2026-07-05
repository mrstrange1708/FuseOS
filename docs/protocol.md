# FuseOS — LAN Device-to-Device Protocol

**Transport:** direct, encrypted connection over the local network · **Encoding:** Protocol Buffers (`proto/`)

This is the **data plane**: the actual clipboard and file bytes moving **directly between two trusted devices**. It never involves the server or the database. The control plane ([api.md](api.md)) only *introduces* the devices (exchanges LAN addresses and public keys); everything below happens peer-to-peer.

---

## 1. Discovery & connection

1. **Discovery:** each device advertises/browses the mDNS service `_fuseos._tcp` on the LAN (NSD on Android, Bonjour/`Network.framework` on macOS). The control plane's `/signal` also supplies a peer's current `lanAddress` as a fast path / fallback to raw mDNS.
2. **Connect:** the initiating device opens a **TLS/DTLS** connection directly to the peer's LAN address.
3. **Peer authentication:** both sides verify the other's **device public key** against the trust established at pairing ([schema.md](schema.md) `device_trust`). An unknown or untrusted key is rejected — a device only ever syncs with its owner's paired devices.
4. **Maintain:** the channel is persistent and bidirectional; `HEARTBEAT` keeps it alive; loss triggers automatic reconnection with backoff.

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

## 6. File transfer flow

1. Sender emits `FILE_META` (name, size, mime, checksum).
2. Sender streams ordered `FILE_CHUNK` messages.
3. Receiver reassembles, verifies the checksum, and offers/saves the file (Storage Access Framework on Android; save panel / Downloads on macOS).
4. Receiver emits `ACK` on success. A failed/interrupted transfer is retried at the transport layer — **never queued on the server**.
5. Images larger than a single message use the same chunking mechanism.

## 7. Security

- **End-to-end encryption** on the channel (TLS/DTLS); session keys per connection.
- **Peer authentication** by device public key against `device_trust`.
- **Integrity**: message authentication on every frame; file checksums verified on receipt.
- Because payloads never touch the server, there is no server-side exposure of clipboard/file content.

## 8. Failure behavior (fail soft)

- A dropped frame or lost peer degrades gracefully: the channel reconnects with backoff; the app never crashes on data-plane errors.
- No indefinite queuing of clipboard events — if a peer is offline, the copy simply isn't delivered (the clipboard is not a durable outbox in v1).
- Heartbeats detect half-open connections and trigger reconnect.
