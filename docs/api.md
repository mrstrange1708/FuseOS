# FuseOS — Control-Plane API

**Server:** Node 22 + TypeScript + Fastify · **Auth:** Better Auth (JWT) · **Real-time:** `ws` at `/signal` · **Jobs:** Inngest

This is the **control plane only**: identity, device registry, presence, and LAN signaling. **No clipboard or file payloads pass through these endpoints** — that traffic is device-to-device (see [protocol.md](protocol.md)).

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
| DELETE | `/devices/:id` | **Not implemented.** Revoke/remove a device (cascades trust) — lands when device management becomes a screen |

**`POST /devices`**
```jsonc
// request  (battery optional, 0–100)
{ "name": "Pixel 8", "platform": "android", "publicKey": "base64…", "battery": 47 }
// response 201
{ "id": "uuid", "name": "Pixel 8", "platform": "android", "createdAt": "…" }
```
Validation: `platform ∈ {android, macos}`, `name` length 1–100, `publicKey` non-empty and unique. Bound to the caller's user. **Idempotent by `publicKey`** — a client may call this on every launch and always gets back its stable device id.

**`GET /devices`** — lists the caller's devices for the dashboard. Optional `?self=<deviceId>` marks which row is the caller; every other row on the account comes back `trusted: true` (see [Trust](#trust) below). Without `?self=` nothing is flagged — "other" has no reference point.
```jsonc
// response 200
{ "devices": [
  { "id": "uuid", "name": "Mac mini", "platform": "macos",
    "online": true, "battery": 88, "lastSeen": "…", "trusted": true, "isSelf": false }
] }
```
`online` and `battery` reflect live `/signal` presence (falling back to the last persisted value).

## Trust

**There is no pairing endpoint.** Two devices are trusted because they are on the same
account: both proved who they are at sign-in, and FuseOS links one user's own devices by
design (see the v1 scope in CLAUDE.md), so a pairing code asked the user to prove a second
time what the login already established. Installing the app on the second device and
signing in is the entire link step.

Concretely, `trustedPeerIds(deviceId)` (`server/src/devices/trust.ts`) is "every other
device with the same `user_id`". Nothing is persisted at link time, so there is no
`device_trust` or `pairing_codes` table and no code to expire.

The consequence for the client is that a new device needs no user action beyond signing
in: it registers, opens `/signal`, and the account's other devices receive `peer-online`
with everything needed to dial it.

## WebSocket — `/signal`

Authenticated by a **first `hello` frame carrying the bearer token** (dev stand-in; a JWT via `Sec-WebSocket-Protocol` under Better Auth). Carries **presence and LAN-address signaling only — never payloads.** A socket that doesn't authenticate within 5s is closed.

Client → server:
```jsonc
{ "type": "hello", "token": "…", "deviceId": "uuid", "lanAddress": "192.168.1.20:47100", "battery": 90 }
{ "type": "heartbeat", "battery": 88, "lanAddress": "192.168.1.20:47100" }
```
Server → client:
```jsonc
{ "type": "hello-ok",     "deviceId": "uuid", "peers": [ { "deviceId": "uuid", "name": "…", "platform": "macos", "publicKey": "base64…", "lanAddress": "…", "battery": 88, "online": true } ] }
{ "type": "peer-online",  "deviceId": "uuid", "name": "…", "platform": "…", "publicKey": "base64…", "lanAddress": "…", "battery": 88 }
{ "type": "peer-update",  "deviceId": "uuid", "battery": 42, "lanAddress": "192.168.1.20:47100" }
{ "type": "peer-offline", "deviceId": "uuid" }
```

Semantics:
- On `hello`, the server authenticates the token, marks the device online, updates `last_seen`/`battery`, replies with `hello-ok` (its trusted, online peers), and relays `peer-online` to those peers. This is the introduction that lets the two devices open a **direct** LAN connection — and, for a device signing in for the first time, it is also the whole linking step.
- `battery` is operational presence metadata (never a user payload); `peer-update` propagates changes to trusted peers for the dashboard.
- A peer card carries `publicKey` and `lanAddress` together because both are needed to open the LAN channel: the address says where to dial, the key says who must answer. `peer-update` fires when either `battery` or `lanAddress` changes — an address change matters because a peer that moved is unreachable until its peers hear about it.
- Heartbeats keep the socket alive; a missed threshold marks the device offline. An Inngest presence-timeout sweep self-heals stale state if a socket dies uncleanly.
- The server does not proxy any clipboard/file data — after the introduction, devices talk directly (see [protocol.md](protocol.md)).

## Inngest functions (durable)

| Function | Trigger | Does |
| --- | --- | --- |
| `presence/sweep-timeouts` | cron | Marks devices offline whose heartbeat lapsed |
| `auth/send-verification` | user created | Sends email verification |

## Observability

The server reports errors to **Sentry** and product analytics to **PostHog** — **operational metadata only, never user payloads**. The analytics `capture()` helper enforces this with a guard that throws on payload-like properties. See [observability.md](observability.md).

## Not in the control plane (by design)

- Clipboard sync, image sync, file transfer — **device-to-device over the LAN** ([protocol.md](protocol.md)).
- Any storage of user payloads.
- Off-LAN relaying (future roadmap).
