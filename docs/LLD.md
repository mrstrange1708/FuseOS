# FuseOS — Low-Level Design (LLD)

**Version:** v2.0
**Status:** Approved for build

> Supersedes the original `LLD_v1.md`. That version claimed "the backend is always the coordinator" and routed clipboard events through the backend, contradicting the HLD. **Corrected here:** the backend is a control plane only; the **data plane is LAN-direct** and no clipboard/file payload ever transits the server. The one idea kept from the old LLD is the loop-prevention rule (§6).

This document describes *how* FuseOS is implemented. It points into the contract docs: [schema.md](schema.md) (database), [api.md](api.md) (control-plane REST + WebSocket), [protocol.md](protocol.md) (LAN wire format).

---

## 1. System decomposition

| Concern | Where | Notes |
| --- | --- | --- |
| Identity, sessions, JWT | `server/` (Better Auth) | source of truth in Postgres |
| Device registry, pairing, trust | `server/` (Fastify + Drizzle) | Postgres, constraint-enforced |
| Presence & LAN signaling | `server/` `/signal` WebSocket (`ws`) | no payloads |
| Durable async jobs | `server/` (Inngest) | expiry, sweeps, notifications |
| Clipboard/file transport | client ⇄ client (LAN) | protobuf over encrypted channel |
| Clipboard capture/injection | native clients | `ClipboardManager` / `NSPasteboard` |

## 2. Device lifecycle (state machine)

```
UNREGISTERED
   │  register (JWT + device pubkey) → server
   ▼
REGISTERED (not paired)
   │  pairing complete (trust established)
   ▼
PAIRED / OFFLINE ──── connect to /signal ────► PAIRED / ONLINE
   ▲                                               │
   │            LAN peer connection established     ▼
   └──────────── disconnect / network loss ──── SYNCING (data plane live)
```

- **REGISTERED → PAIRED:** via the pairing flow (§4). A device may have multiple trusted peers (2–3 devices total per account in v1).
- **ONLINE:** connected to the control-plane `/signal` socket; presence is visible to the user's other devices.
- **SYNCING:** a direct LAN data-plane channel to a trusted peer is open; clipboard/file events flow.
- Transitions are event-driven; reconnection is automatic with backoff.

## 3. Control-plane request handling

- Every request/socket carries a Better Auth **JWT**; Fastify validates it before any handler runs.
- Input is validated with **Zod** at the boundary; only validated, typed data reaches a Drizzle query.
- Multi-row writes (e.g. pairing: create trust + mark code used) run in a **transaction**.
- Errors are typed and returned explicitly (fail loud on the control plane).

Full endpoint list and payloads: [api.md](api.md).

## 4. Pairing flow (detailed)

1. **Initiate** (`POST /pairing/initiate`, device A): server generates a random short code, stores a `pairing_codes` row (`user_id`, `code`, `expires_at` ~ minutes, `used_at = null`), returns the code. An **Inngest** job is scheduled to expire it.
2. **Claim** (`POST /pairing/claim`, device B): server validates the code (exists, same `user_id`, not expired, not used) inside a transaction, exchanges the two devices' public keys, writes a `device_trust` relationship, and marks the code `used_at = now()`.
3. **Notify:** the server pushes a pairing-complete event to both devices over `/signal` (delivery made durable via Inngest).
4. Both devices persist the peer's public key locally and may now establish the data-plane channel.

Codes are **short-lived, one-time, user-scoped** — a code can only ever pair two devices of the same account.

## 5. Presence & signaling (`/signal`)

- On connect (JWT-authenticated), the device is marked online and `last_seen` is updated; its trusted peers are notified.
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
- `FILE_META` (name, size, mime, checksum) → ordered `FILE_CHUNK` stream → receiver verifies checksum → `ACK`. Progress derived from bytes received. Failed transfers are retried at the transport layer, not queued on the server.

## 7. Error handling

| Plane | Strategy |
| --- | --- |
| Control (REST/WS) | Fail loud: typed error responses, validated input, transactional writes. |
| Data (LAN) | Fail soft: a dropped packet or lost peer degrades gracefully and reconnects; never crash the app; no indefinite queuing. |
| Durable jobs | Inngest retries with backoff; nothing critical is fire-and-forget. |

## 8. Constraints & invariants (must hold)

- No clipboard/file payload ever reaches the server or the database.
- The database is authoritative only for identity, devices, pairing codes, and trust.
- Received events are never re-emitted (§6).
- Pairing codes are one-time, time-limited, user-scoped.
- All external input is Zod-validated before touching Drizzle.
- Schema changes are additive/backward-compatible where possible (see [schema.md](schema.md)).

## 9. Known limitations (accepted for v1)

- Same-LAN only; no off-network relay (roadmap item).
- No offline clipboard queue.
- Clipboard/file size bounded by transport limits.
- Last-write-wins only; no rich conflict resolution.
