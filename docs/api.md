# FuseOS — Control-Plane API

**Server:** Node 22 + TypeScript + Fastify · **Auth:** Better Auth (JWT) · **Real-time:** `ws` at `/signal` · **Jobs:** Inngest

This is the **control plane only**: identity, device registry, pairing, presence, and LAN signaling. **No clipboard or file payloads pass through these endpoints** — that traffic is device-to-device (see [protocol.md](protocol.md)).

Conventions:
- All bodies are JSON; all input is **Zod-validated** at the boundary before any DB access.
- All non-auth endpoints and the WebSocket require a valid **JWT** (`Authorization: Bearer <jwt>`), issued by Better Auth.
- Errors are typed: `{ "error": { "code": string, "message": string } }` with an appropriate HTTP status.

---

## Auth (Better Auth)

Better Auth mounts its own routes (email/password sign-up, sign-in, session, refresh, sign-out) and issues a **JWT** via its JWT plugin. The JWT authorizes both REST calls and the `/signal` WebSocket.

| Method | Path | Purpose |
| --- | --- | --- |
| POST | `/auth/sign-up/email` | Create account (email + password) |
| POST | `/auth/sign-in/email` | Sign in → session + JWT |
| POST | `/auth/token` | Obtain / refresh JWT |
| POST | `/auth/sign-out` | Invalidate session |

> Exact route shapes follow Better Auth's mounted handler; treat the above as the logical surface. Email verification is sent via an Inngest job.

## Devices

| Method | Path | Purpose |
| --- | --- | --- |
| POST | `/devices` | Register this device (name, platform, public_key) |
| GET | `/devices` | List the caller's devices |
| DELETE | `/devices/:id` | Revoke/remove a device (cascades trust) |

**`POST /devices`**
```jsonc
// request  (battery optional, 0–100)
{ "name": "Pixel 8", "platform": "android", "publicKey": "base64…", "battery": 47 }
// response 201
{ "id": "uuid", "name": "Pixel 8", "platform": "android", "createdAt": "…" }
```
Validation: `platform ∈ {android, macos}`, `name` length 1–100, `publicKey` non-empty and unique. Bound to the caller's user. **Idempotent by `publicKey`** — a client may call this on every launch and always gets back its stable device id.

**`GET /devices`** — lists the caller's devices for the dashboard. Optional `?self=<deviceId>` flags which peers the caller is paired with.
```jsonc
// response 200
{ "devices": [
  { "id": "uuid", "name": "Mac mini", "platform": "macos",
    "online": true, "battery": 88, "lastSeen": "…", "trusted": true, "isSelf": false }
] }
```
`online` and `battery` reflect live `/signal` presence (falling back to the last persisted value).

## Pairing

| Method | Path | Purpose |
| --- | --- | --- |
| POST | `/pairing/initiate` | Issue a short-lived pairing code (device A) |
| POST | `/pairing/claim` | Redeem a code, establish trust (device B) |

**`POST /pairing/initiate`**
```jsonc
// request  { "deviceId": "uuid-of-A" }
// response 201
{ "code": "A7X2-9QKM", "expiresAt": "2026-07-05T12:34:56Z" }
```
The code is **8 uppercase alphanumerics shown grouped `XXXX-XXXX`** (alphabet omits the ambiguous `I O 0 1`), valid for 5 minutes. Creates a `pairing_codes` row scoped to the user and to the initiating `device_id`; an Inngest job expires it. The claim side normalizes leniently (case- and dash-insensitive).

**`POST /pairing/claim`**
```jsonc
// request  { "deviceId": "uuid-of-B", "code": "A7X2-9QKM" }
// response 200
{ "trustedWith": { "deviceId": "uuid-of-A", "name": "Mac mini", "platform": "macos", "publicKey": "base64…" } }
```
In a single transaction: validate the code (exists, same user, not expired, not used), write `device_trust` (canonically ordered), mark the code `used_at`. Returns A to B; A is notified over `/signal` with a `paired` event. Errors: `code_invalid`, `code_expired`, `same_device`.

## WebSocket — `/signal`

Authenticated by a **first `hello` frame carrying the bearer token** (dev stand-in; a JWT via `Sec-WebSocket-Protocol` under Better Auth). Carries **presence, pairing notifications, and LAN-address signaling only — never payloads.** A socket that doesn't authenticate within 5s is closed.

Client → server:
```jsonc
{ "type": "hello", "token": "…", "deviceId": "uuid", "lanAddress": "192.168.1.20:47100", "battery": 90 }
{ "type": "heartbeat", "battery": 88, "lanAddress": "192.168.1.20:47100" }
```
Server → client:
```jsonc
{ "type": "hello-ok",     "deviceId": "uuid", "peers": [ { "deviceId": "uuid", "name": "…", "platform": "macos", "lanAddress": "…", "battery": 88, "online": true } ] }
{ "type": "peer-online",  "deviceId": "uuid", "name": "…", "platform": "…", "lanAddress": "…", "battery": 88 }
{ "type": "peer-update",  "deviceId": "uuid", "battery": 42 }
{ "type": "peer-offline", "deviceId": "uuid" }
{ "type": "paired",       "deviceId": "uuid", "name": "…", "platform": "…", "publicKey": "base64…" }
```

Semantics:
- On `hello`, the server authenticates the token, marks the device online, updates `last_seen`/`battery`, replies with `hello-ok` (its trusted, online peers), and relays `peer-online` to those peers. This is the introduction that lets the two devices open a **direct** LAN connection.
- `battery` is operational presence metadata (never a user payload); `peer-update` propagates changes to trusted peers for the dashboard.
- Heartbeats keep the socket alive; a missed threshold marks the device offline. An Inngest presence-timeout sweep self-heals stale state if a socket dies uncleanly.
- The server does not proxy any clipboard/file data — after the introduction, devices talk directly (see [protocol.md](protocol.md)).

## Inngest functions (durable)

| Function | Trigger | Does |
| --- | --- | --- |
| `pairing/expire-code` | scheduled at code creation | Marks/prunes the code after `expires_at` |
| `presence/sweep-timeouts` | cron | Marks devices offline whose heartbeat lapsed |
| `pairing/notify` | pairing completed | Durable delivery of the `paired` event |
| `auth/send-verification` | user created | Sends email verification |

## Observability

The server reports errors to **Sentry** and product analytics to **PostHog** — **operational metadata only, never user payloads**. The analytics `capture()` helper enforces this with a guard that throws on payload-like properties. See [observability.md](observability.md).

## Not in the control plane (by design)

- Clipboard sync, image sync, file transfer — **device-to-device over the LAN** ([protocol.md](protocol.md)).
- Any storage of user payloads.
- Off-LAN relaying (future roadmap).
