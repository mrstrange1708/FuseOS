# FuseOS — Low-Level Design (LLD)

**Version:** v2.0
**Status:** Approved for build

> Supersedes the original `LLD_v1.md`. That version claimed "the backend is always the coordinator" and routed clipboard events through the backend, contradicting the HLD. **Corrected here:** the backend is a control plane only; the **data plane is LAN-direct** and no clipboard/file payload ever transits the server. The one idea kept from the old LLD is the loop-prevention rule (§6).

This document describes *how* FuseOS is implemented. It points into the contract docs: [schema.md](schema.md) (database), [api.md](api.md) (control-plane REST + WebSocket), [protocol.md](protocol.md) (LAN wire format).

---

## 1. System decomposition

| Concern | Where | Notes |
| --- | --- | --- |
| Identity, sessions | `server/` (Better Auth) | source of truth in Postgres |
| Device registry (and the trust derived from it) | `server/` (Fastify + Drizzle) | Postgres, constraint-enforced |
| Presence & LAN signaling | `server/` `/signal` WebSocket (`ws`) | no payloads |
| Durable async jobs | `server/` (Inngest) | expiry, sweeps, notifications |
| Clipboard/file transport | client ⇄ client (LAN) | protobuf over encrypted channel |
| Clipboard capture/injection | native clients | `ClipboardManager` / `NSPasteboard` |

## 2. Device lifecycle (state machine)

```
UNREGISTERED
   │  register (session token + device pubkey) → server
   ▼
REGISTERED
   │  (trusted with every other device on the account — nothing to do)
   ▼
OFFLINE ──── connect to /signal ────► ONLINE
   ▲                                               │
   │            LAN peer connection established     ▼
   └──────────── disconnect / network loss ──── SYNCING (data plane live)
```

- **REGISTERED:** registration is the whole of it — the device is trusted with every other device on the account from that moment (§4). 2–3 devices per account in v1.
- **ONLINE:** connected to the control-plane `/signal` socket; presence is visible to the user's other devices.
- **SYNCING:** a direct LAN data-plane channel to a trusted peer is open; clipboard/file events flow.
- Transitions are event-driven; reconnection is automatic with backoff.

## 3. Control-plane request handling

- Every request/socket carries a Better Auth **session token** (`Authorization: Bearer`); Fastify validates it before any handler runs.
- Input is validated with **Zod** at the boundary; only validated, typed data reaches a Drizzle query.
- Multi-row writes run in a **transaction**.
- Errors are typed and returned explicitly (fail loud on the control plane).

Full endpoint list and payloads: [api.md](api.md).

## 4. Linking flow (detailed)

There is no pairing step. `trustedPeerIds(deviceId)` (`server/src/devices/trust.ts`) means
"every other device with the same `user_id`", so linking is a consequence of signing in:

1. **Register** (`POST /devices`): the new device sends its name, platform, and public key
   and gets back its stable device id. Idempotent on the public key.
2. **Connect** (`/signal` `hello`): the server replies `hello-ok` with the account's other
   online devices — each card carrying its public key and LAN address — and relays
   `peer-online` to them.
3. Both sides now hold what they need and open the data-plane channel directly.

A public key already registered to a **different** account is refused (`409
public_key_taken`) rather than reassigned: public keys are not secret, so honouring the
claim would let anyone who learns one take over that device. The client's move is to mint
a fresh identity and retry, which is what both apps do.

## 5. Presence & signaling (`/signal`)

- On connect (session-token authenticated), the device is marked online and `last_seen` is updated; its trusted peers are notified.
- The device publishes its current **LAN address**; the server relays it to trusted, online peers so they can open a direct connection (signaling only — no payloads).
- Heartbeats keep the socket alive; a missed-heartbeat threshold marks the device offline. An **Inngest** presence-timeout sweep self-heals stale "online" rows if a socket dies uncleanly.

## 6. Data plane: message handling & loop prevention

Once two trusted devices have a direct LAN channel (see [protocol.md](protocol.md)):

- Messages are **protobuf**-encoded (`proto/`) over an encrypted (TLS/DTLS) connection.
- **Every event carries `source_device_id` and a monotonic `seq`.**
- **Loop-prevention invariant:** a device that *receives* an event **applies it but never re-emits** it. Only user-initiated local changes originate new events. Conflicts resolve **last-write-wins** by `seq`/timestamp. This is the single rule that prevents infinite clipboard loops across devices; do not weaken it.
- Duplicate suppression: a receiver ignores an event whose `(source_device_id, seq)` it has already applied.

### Clipboard events
- `CLIP_TEXT` — UTF-8 text payload.
- `CLIP_IMAGE` — image bytes + mime; for larger images, chunk as with files.

### File transfer
- `FILE_META` (name, size, mime, checksum) → ordered `FILE_CHUNK` stream → receiver verifies checksum → `ACK`. Either end can stop with `FILE_CANCEL`. Progress is derived from bytes sent or received. There is no retry or resume: a failed transfer is re-sent by the user, and nothing is ever queued on the server. See `docs/protocol.md` §6.

## 7. Error handling

| Plane | Strategy |
| --- | --- |
| Control (REST/WS) | Fail loud: typed error responses, validated input, transactional writes. |
| Data (LAN) | Fail soft: a dropped packet or lost peer degrades gracefully and reconnects; never crash the app; no indefinite queuing. |
| Durable jobs | Inngest retries with backoff; nothing critical is fire-and-forget. |

## 8. Constraints & invariants (must hold)

- No clipboard/file payload ever reaches the server or the database.
- The database is authoritative only for identity and the device registry.
- Received events are never re-emitted (§6).
- A device's public key belongs to exactly one account and is never reassigned.
- All external input is Zod-validated before touching Drizzle.
- Schema changes are additive/backward-compatible where possible (see [schema.md](schema.md)).

## 9. Known limitations (accepted for v1)

- Same-LAN only; no off-network relay (roadmap item).
- No offline clipboard queue.
- Clipboard/file size bounded by transport limits.
- Last-write-wins only; no rich conflict resolution.
