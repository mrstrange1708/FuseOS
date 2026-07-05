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
// request
{ "name": "Pixel 8", "platform": "android", "publicKey": "base64…" }
// response 201
{ "id": "uuid", "name": "Pixel 8", "platform": "android", "createdAt": "…" }
```
Validation: `platform ∈ {android, macos}`, `name` length 1–100, `publicKey` non-empty and unique. Bound to the JWT's user.

## Pairing

| Method | Path | Purpose |
| --- | --- | --- |
| POST | `/pairing/initiate` | Issue a short-lived pairing code (device A) |
| POST | `/pairing/claim` | Redeem a code, establish trust (device B) |

**`POST /pairing/initiate`**
```jsonc
// request  { "deviceId": "uuid-of-A" }
// response 201
{ "code": "K7QP2M", "expiresAt": "2026-07-05T12:34:56Z" }
```
Creates a `pairing_codes` row scoped to the user; schedules an Inngest job to expire it.

**`POST /pairing/claim`**
```jsonc
// request  { "deviceId": "uuid-of-B", "code": "K7QP2M" }
// response 200
{ "trustedWith": { "deviceId": "uuid-of-A", "publicKey": "base64…" } }
```
In a single transaction: validate the code (exists, same user, not expired, not used), write `device_trust`, mark the code `used_at`. Returns A's public key to B; A is notified over `/signal`. Errors: `code_invalid`, `code_expired`, `code_used`.

## WebSocket — `/signal`

JWT-authenticated (token via `Sec-WebSocket-Protocol` or a first auth frame). Carries **presence, pairing notifications, and LAN-address signaling only — never payloads.**

Client → server:
```jsonc
{ "type": "hello", "deviceId": "uuid", "lanAddress": "192.168.1.20:47100" }
{ "type": "heartbeat" }
```
Server → client:
```jsonc
{ "type": "peer-online",  "deviceId": "uuid", "lanAddress": "192.168.1.31:47100" }
{ "type": "peer-offline", "deviceId": "uuid" }
{ "type": "paired",       "deviceId": "uuid", "publicKey": "base64…" }
```

Semantics:
- On `hello`, the server marks the device online, updates `last_seen`, and relays its `lanAddress` to trusted, online peers (and their addresses back). This is the introduction that lets the two devices open a **direct** LAN connection.
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
