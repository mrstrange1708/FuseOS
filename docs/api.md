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
| POST | `/auth/google` | `{ idToken }` — a Google ID token | `200 { token, user }`; signs up on first use |
| POST | `/auth/request-password-reset` | `{ email }` | `200 { ok: true }` whether or not the account exists (no enumeration); `429 rate_limited` |
| POST | `/auth/reset-password` | `{ token, newPassword (8–200) }` | `200 { ok: true }` and **every session is revoked** (a forgotten and a stolen password look alike); `400 invalid_token`. Called by the website's `/reset` page, so this route alone answers CORS — for `WEB_URL`'s origin only |

Emailed links (reset, confirmation) are built from `BETTER_AUTH_URL`, which the server requires in production: without it Better Auth takes its address from each request's `Host` header, and a forged `Host` on a reset request would send the victim a link — and their token — to someone else's site.
| GET | `/auth/verify-email?token=` | — | The link in the confirmation email; redirects to the website's `/verified` (or `/verified?error=expired`) |
| POST | `/auth/sign-out` | — (bearer token) | `200`; the token stops working at once |

Errors: `400 invalid_request` (failed validation), `409 email_taken`, `401 invalid_credentials` (unknown email and wrong password answer the same), anything else Better Auth reports as its own code, lower-cased. Google adds `401 invalid_google_token`, `409 use_password` and `503 google_unavailable` (below).

**Sign in with Google.** Each app gets the ID token on the device and posts it; the server verifies it against Google's keys (`/auth/sign-in/social` in Better Auth), so no redirect ever reaches the server. Google Cloud project `fuseos-510109` holds four clients:

| Client | Used by | Configured where |
| --- | --- | --- |
| Web (`…k5cnmdsu…`) + secret | the server; the audience of Android's tokens | `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` in the server env |
| Android debug, Android release | Google recognising the APK by package + SHA-1 | Google Cloud only (nothing in code) |
| iOS type (`…lmb0vpom…`) | the Mac: `ASWebAuthenticationSession`, PKCE, reversed-id redirect, no secret | `GoogleSignIn.swift`; `GOOGLE_MAC_CLIENT_ID` in the server env |

Android uses Credential Manager (`GetGoogleIdOption` with the web client as server client id). Either client id is an accepted audience. Google sign-in is off (`503 google_unavailable`) until all three env values are set.

**Linking.** A Google sign-in whose email already has a FuseOS account is linked only if that account's email is verified (Better Auth's `requireLocalEmailVerified`). Otherwise it is refused with `409 use_password`: anyone can register an address without proving it, and linking would let them share — and trust devices on — the real owner's account. Once email verification ships, a verified account links on its first Google sign-in.

**Tokens are opaque session tokens (the bearer plugin), not JWTs.** Each request costs one indexed lookup in `session`. JWTs would save that lookup, but REST is off the clipboard hot path, and a session token can be revoked at once, which a JWT cannot. Sessions last 90 days and are extended at most once a day while the device uses them. A continuity app that signs you out weekly is not worth having.

> Email verification is sent on sign-up via an Inngest job (below). Sign-in does not wait for it (`requireEmailVerification` off); a confirmed email is what lets a Google sign-in link to the account.

## Feedback

`POST /feedback` — the website's **Report a bug** form (`/report`). Body: `{ kind: bug|idea|other, platform: mac|android|both|website, message (10–5000), steps?, appVersion?, email?, website? }`. Answers `{ ok: true }`; `400` when the message is too short, `429` after 5 reports an hour from one address (in-memory, one instance). `website` is a honeypot: filled means a bot, which is answered `ok` and dropped. CORS for `WEB_URL`'s origin only (`http/website-cors.ts`, shared with `/auth/reset-password`). The report travels as an Inngest event and is emailed to the owner — it is feedback someone chose to send, not synced content, and the form asks people not to paste anything private.

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
{ "type": "peer-update",  "deviceId": "uuid", "name": "nano" }             // a rename
{ "type": "peer-offline", "deviceId": "uuid" }
```

Semantics:
- On `hello`, the server authenticates the token, marks the device online, updates `last_seen`/`battery`, replies with `hello-ok` (its trusted, online peers), and relays `peer-online` to those peers. This is the introduction that lets the two devices open a **direct** LAN connection — and, for a device signing in for the first time, it is also the whole linking step.
- `battery` is operational presence metadata (never a user payload); `peer-update` propagates changes to trusted peers for the dashboard.
- A peer card carries `publicKey` and `lanAddress` together because both are needed to open the LAN channel: the address says where to dial, the key says who must answer. `peer-update` fires when either `battery` or `lanAddress` changes — an address change matters because a peer that moved is unreachable until its peers hear about it. It also fires with just `name` when an online device re-registers (`POST /devices`), because both apps draw names from their `GET /devices` roster and refetch it when a peer's announced name differs; without it a rename showed on the other device only after a restart. Fields a `peer-update` omits keep their last value.
- Heartbeats keep the socket alive; a missed threshold marks the device offline. An Inngest presence-timeout sweep self-heals stale state if a socket dies uncleanly.
- The server does not proxy any clipboard/file data — after the introduction, devices talk directly (see [protocol.md](protocol.md)).

## Inngest functions (durable)

Served at `/api/inngest` (`server/src/jobs/`). Locally the Inngest dev server (`inngest` mprocs pane, `INNGEST_DEV=1`); hosted, Inngest Cloud with `INNGEST_EVENT_KEY` + `INNGEST_SIGNING_KEY`. Requests queue events with `emit()`, which never fails the request (a failure to queue goes to Sentry) and does nothing under test, so the suite never emails anyone. Emails go through Resend (`RESEND_API_KEY`, `EMAIL_FROM`) and only to **confirmed** addresses, except the confirmation itself.

| Function | Trigger | Does |
| --- | --- | --- |
| `presence-sweep-timeouts` | cron, every minute | Terminates `/signal` sockets silent for 2 min (clients heartbeat every 20 s); each socket's close handler sends `peer-offline`. A phone that lost Wi-Fi without a FIN otherwise stayed "online" for hours. |
| `auth-send-verification` | `auth/verification.requested` (sign-up) | Emails the confirmation link; the link (`GET /auth/verify-email`) answers with a small page |
| `auth-welcome` | `auth/email.verified` | Welcome email with the download link |
| `devices-new-device-alert` | `devices/device.added` (a new public key, not a re-register) | "New device on your FuseOS account" — every device on an account is trusted with its clipboard, so the owner hears of each one. Not for the first device. |
| `auth-password-reset` | `auth/password-reset.requested` | The reset link — to confirmed or unconfirmed addresses alike, since only the mailbox owner can use it |
| `feedback-email` | `feedback/submitted` (`POST /feedback`) | Emails a website bug report or idea to `FEEDBACK_TO`, with Reply-To set to the reporter's address when they gave one |
| `releases-announce` | `releases/published`, sent by `release.yml` for a plain `vX.Y.Z` tag with the tag as event id (no double send) | One **Resend Broadcast** to the release list. Confirmed users join it with the welcome email; Resend keeps unsubscribes. Needs `RESEND_SEGMENT_ID` and a full-access key |

Every email is branded HTML with a plain-text twin (`server/src/email/templates.ts`): inline styles in tables, because mail clients drop `<style>`; a light card, because dark backgrounds get inverted by client dark modes; and anything a person typed is HTML-escaped. Sender: `FuseOS <noreply@fuseos.theshaik.dev>` (verified in Resend: SPF, DKIM and DMARC records under `fuseos.theshaik.dev`).

Events carry ids (`userId`, `deviceId`), never the address: the job reads it when it sends.

## Observability

The server reports errors to **Sentry** and product analytics to **PostHog** — **operational metadata only, never user payloads**. The analytics `capture()` helper enforces this with a guard that throws on payload-like properties. See [observability.md](observability.md).

## Not in the control plane (by design)

- Clipboard sync, image sync, file transfer — **device-to-device over the LAN** ([protocol.md](protocol.md)).
- Any storage of user payloads.
- Off-LAN relaying (future roadmap).
