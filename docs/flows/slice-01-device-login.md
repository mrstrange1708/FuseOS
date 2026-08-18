# Slice 01 — Device Login & Connect

**Status:** Complete. Login, sign-up, device registration, pairing by code, presence, and the direct encrypted LAN connection are all built on Android + macOS. Clipboard text sync followed in [slice-02](slice-02-clipboard-sync.md).
**Goal:** the smallest thing we can actually run and test — log in, know which device you're on, and open a live connection between an Android phone and a Mac on the same Wi-Fi.

> Visual mock: the "Device Login" design review (published artifact). This doc is the spec behind it.

## Built so far
- **Android app** (`clients/android`) — Kotlin + Compose login/sign-up flow → home. Builds a debug APK.
- **macOS app** (`clients/macos`) — SwiftUI login/sign-up flow → home. Builds with `swift build`.
- **The connect space** (`ConnectScreen.kt` · `ConnectView.swift`) — screens 3 and 4 below as one self-advancing screen. Its stage logic lives in `ConnectState.kt` / `ConnectState.swift`: pure, platform-free, and covered by mirrored test suites on both clients, so the two apps cannot drift on what "connected" means.
- **Server auth** (`server/src/auth/dev-auth.ts`) — real `POST /auth/sign-up/email` + `/auth/sign-in/email` (scrypt-hashed), so login works end-to-end today. **Dev stand-in** for Better Auth + PostgreSQL, which replaces it next (in-memory store; users reset on restart).

## The black-and-white scope call

This is deliberately **not** the complete product. We build only the loop **"log in → identify the device → connect the two,"** and ship none of the payload features until that loop is solid.

**In this slice**
- Account sign-up & sign-in (email + password) via Better Auth → JWT.
- **Device Login:** identify and name *this* device; register it (name, platform, public key) or recognise a known install.
- Match/pair with the account's other device via a short one-time code; record trust.
- Live presence + a direct encrypted connection over the same Wi-Fi.

**Not yet — on purpose**
- Clipboard sync (text/images), file transfer, Share-sheet send.
- Screen mirroring, remote control.
- Off-Wi-Fi / relay fallback.

## Screens (both apps: Android Compose · macOS SwiftUI)

1. **Sign in** — email + password, "Create account" fallback. → Better Auth.
2. **Device Login — "What device are you logging in with today?"** *(the defining screen)* — the app detects this hardware (`Pixel 8 · Android`), the user confirms and names it (`Pragya's Pixel`), and continues **as this device**. New device → registered; known install → recognised on sight. "Not this device? Choose another" covers reinstalls / shared accounts.
3. **Connect** *(screens 3 and 4, built as one)* — shows this device above its peer with the link between them, and advances itself through five stages as presence and the LAN channel change. Nothing here polls; it re-derives from the `/signal` presence stream.

   | Stage | Shown when | Way out |
   | --- | --- | --- |
   | `NotPaired` | no paired peers | "Scan a code" → pairing |
   | `PeerOffline` | paired, peer not running the app | waits |
   | `DifferentNetwork` | both online, advertised `lanAddress`es on different /24s | waits; names both networks |
   | `Connecting` | same /24, no channel yet | resolves itself |
   | `Connected` | a live encrypted LAN channel exists | **Continue** → home |

   Only `Connected` offers Continue: past this screen the app assumes a live channel, so letting someone through early only moves the confusion later. The channel is checked before presence — presence can be stale, a channel carrying bytes cannot.

   `DifferentNetwork` compares the /24 of each side's advertised address. The netmask is an assumption (it is what every consumer router and phone hotspot uses, and a peer's address doesn't carry its mask), so it can only ever mislabel the *reason* on screen — `Connected` is still decided by a real channel.

   Onboarding runs once: after the first Continue, launches go straight to home, which shows the same connection status.

## The handshake (maps to existing contracts)

| Step | What happens | Contract |
| --- | --- | --- |
| 1. Authenticate | Verify email+password, issue JWT (authorises REST **and** the `/signal` socket) | [api.md](../api.md) · Better Auth |
| 2. Identify device | Register (name, `platform`, `public_key`) or recognise this install | `POST /devices`, `GET /devices` · `devices` table ([schema.md](../schema.md)) |
| 3. Match & trust | One-time code exchanges public keys, records trust | `POST /pairing/initiate` + `POST /pairing/claim` · `pairing_codes`, `device_trust` |
| 4. Go live | Both join `/signal`, swap LAN addresses, open a direct encrypted link | WebSocket `/signal` → LAN data plane ([protocol.md](../protocol.md)) |

Nothing here puts payloads on the server — this slice only exercises the control plane plus establishing the LAN link; no clipboard/file bytes flow yet.

## "Device Login" — the concept

Unlike a normal app login, FuseOS logins are **device-aware**: signing into the account is step one, but the app must also answer *"which of your devices is this?"* before it can connect anything. That second question — asked as **"What device are you logging in with today?"** — is what registers/selects the device identity for the session and makes the rest of the product (peer devices, pairing, sync) possible. It's the moment the app stops being "an account" and becomes "one of your devices."

## What "test the part" means here

A slice is done when, on two real devices on one Wi-Fi:
1. Both sign in to the same account.
2. Each completes Device Login and appears in the other's device list.
3. First-time pairing via code succeeds; trust persists.
4. A direct encrypted connection opens and presence/heartbeat stays green across a brief network blip (auto-reconnect).

No payload sync is tested in this slice — that's the next one.
