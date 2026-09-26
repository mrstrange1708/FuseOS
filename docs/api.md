# FuseOS — Control-Plane API

**Server:** Node 22 + TypeScript + Fastify · **Auth:** Better Auth (bearer session tokens) · **Real-time:** `ws` at `/signal` · **Jobs:** Inngest

This is the **control plane only**: identity, device registry, presence, and LAN signaling. **No clipboard or file payloads pass through these endpoints** — that traffic is device-to-device (see [protocol.md](protocol.md)).

Conventions:
- All bodies are JSON; all input is **Zod-validated** at the boundary before any DB access.
- All non-auth endpoints and the WebSocket require a valid **session token** (`Authorization: Bearer <token>`), issued by Better Auth at sign-up or sign-in.
- Errors are typed: `{ "error": { "code": string, "message": string } }` with an appropriate HTTP status.

---

## Auth (Better Auth)

Better Auth (`server/src/auth/auth.ts`) serves these routes behind a thin adapter (`auth/routes.ts`). The adapter Zod-validates the body first, and it reshapes Better Auth's `{ code, message }` errors into this API's error shape. So the routes, response bodies and error codes are the same as the dev stand-in's were, and neither client changed.

| Method | Path | Body | Success |
| --- | --- | --- | --- |
| POST | `/auth/sign-up/email` | `{ email, password (8–200), name (1–100) }` | `201 { token, user: { id, email, name, … } }` |
| POST | `/auth/sign-in/email` | `{ email, password }` | `200 { token, user }` |
| POST | `/auth/sign-out` | — (bearer token) | `200`; the token stops working at once |

Errors: `400 invalid_request` (failed validation), `409 email_taken`, `401 invalid_credentials` (unknown email and wrong password answer the same), anything else Better Auth reports as its own code, lower-cased.

**Tokens are opaque session tokens (the bearer plugin), not JWTs.** Each request costs one indexed lookup in `session`. JWTs would save that lookup, but REST is off the clipboard hot path, and a session token can be revoked at once, which a JWT cannot. Sessions last 90 days and are extended at most once a day while the device uses them. A continuity app that signs you out weekly is not worth having.

> Email verification is sent via an Inngest job (not yet wired; `requireEmailVerification` is off).

## Devices

| Method | Path | Purpose |
| --- | --- | --- |
| POST | `/devices` | Register this device (name, platform, public_key) |
| GET | `/devices` | List the caller's devices |
| DELETE | `/devices/:id` | Remove one of the caller's **offline** devices (the stale record a reinstall leaves behind) |

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

**`DELETE /devices/:id`** — `204` on success. `400 invalid_request` for a non-UUID id, `404 device_not_found` when it is not the caller's (another account's device reads the same as a missing one), and `409 device_online` for a device with a live `/signal` socket: a live device is signed out on the device itself, not removed from afar. Both clients offer it on offline devices in their device lists.

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

### Manual linking (the safety net)

Automatic linking is the path; these two endpoints are the hand-crank for when it hasn't
happened — a socket that dropped, presence gone stale, a device the other side simply
hasn't heard about. **They do not grant trust** (same account already does). They force the
peer-card exchange that `/signal` normally delivers on its own.

| Method | Path | Purpose |
| --- | --- | --- |
| POST | `/pairing/initiate` | Issue a short-lived code (device A) |
| POST | `/pairing/claim` | Redeem it; both ends get the other's peer card (device B) |

**`POST /pairing/initiate`**
```jsonc
// request  { "deviceId": "uuid-of-A" }
// response 201
{ "code": "A7X2-9QKM", "expiresAt": "2026-08-19T12:34:56Z" }
```
**8 uppercase alphanumerics shown grouped `XXXX-XXXX`** (the alphabet omits the ambiguous
`I O 0 1`), valid for 5 minutes, held in memory on the server rather than in a table — a
code means nothing once claimed, so persisting it would buy only survival across a restart.

The initiating device may also render the code as a **QR** carrying
`fuseos://pair?code=XXXX-XXXX` — the same code by another route, so no extra endpoint and
no extra trust. macOS shows one (CoreImage) and Android scans it (CameraX + ML Kit); the
scanner accepts only that URI or a bare complete code, so an unrelated QR can never become
a claim. Parsing rules live in `PairingCode` on both clients with mirrored test vectors.

**`POST /pairing/claim`**
```jsonc
// request  { "deviceId": "uuid-of-B", "code": "A7X2-9QKM" }
// response 200
{ "trustedWith": { "deviceId": "uuid-of-A", "name": "Mac mini", "platform": "macos",
                   "publicKey": "base64…", "lanAddress": "192.168.1.10:47100" } }
```
Validates the code (exists, **same account**, not spent), returns A's card to B, and pushes
B's card to A over `/signal` as `peer-online`. The code is spent on claim, so a
shoulder-surfed one cannot be replayed. Errors: `code_invalid`, `same_device`,
`device_not_found`. A code issued on another account reads as `code_invalid` — whether one
exists elsewhere is not the caller's business.

## WebSocket — `/signal`

Authenticated by a **first `hello` frame carrying the session token**, checked against Better Auth's `session` table once per connection. Carries **presence and LAN-address signaling only — never payloads.** A socket that doesn't authenticate within 5s is closed.

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
