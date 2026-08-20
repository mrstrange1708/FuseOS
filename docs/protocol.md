# FuseOS — LAN Device-to-Device Protocol

**Transport:** direct, encrypted connection over the local network · **Encoding:** Protocol Buffers (`proto/`)

This is the **data plane**: the actual clipboard and file bytes moving **directly between two trusted devices**. It never involves the server or the database. The control plane ([api.md](api.md)) only *introduces* the devices (exchanges LAN addresses and public keys); everything below happens peer-to-peer.

---

## 1. Discovery & connection

1. **Discovery:** `/signal` relays each peer's current `lanAddress` and `publicKey` on the peer card — the address says where to dial, the key says who must answer. That is everything needed to open the channel, so **mDNS (`_fuseos._tcp`) is not implemented yet**; it is the fallback for when linking has to work without internet, and it is deliberately deferred.
2. **Who dials:** every device listens on an ephemeral TCP port, but only the device with the **lexicographically lower device id** dials. Without that tie-break both ends dial at once and every pair ends up with two half-used connections.
3. **Connect & authenticate:** the dialer opens a plain TCP connection and both sides exchange a handshake frame — `[2-byte BE id length][device id UTF-8][32-byte nonce]` — in the clear. The device id is there because the listening side sees only an IP address and needs to know whose key to look up. Each side then requires the peer's **static P-256 public key** to be one the control plane vouched for ([schema.md](schema.md) `device_trust`); an unknown key closes the socket before anything is decrypted.
4. **Channel keys:** ECDH over the two static keys, salted with both nonces, expanded by HKDF-SHA256 into **one key per direction** (`fuseos:lan:v1:low-to-high` and `…:high-to-low`, ordered by device id so both ends agree without extra negotiation). Every frame after the handshake is `[4-byte BE length][AES-GCM ciphertext || 16-byte tag]` over a serialised `Envelope`, with the frame counter as the GCM nonce.

   This is TLS-shaped rather than literally TLS: the same guarantees (authenticated peers, per-session keys, per-frame integrity) without a certificate chain, because the control plane already distributes the keys that a PKI would otherwise establish.
5. **Maintain:** the channel is persistent and bidirectional; a `Heartbeat` envelope every 15s keeps it alive; loss triggers reconnection with exponential backoff capped at 15s.

> **No forward secrecy.** The ECDH is static-static, so an attacker holding a device's private key can decrypt recorded sessions. The upgrade is ephemeral keys plus signatures (Noise IK); it was skipped because it costs a full handshake protocol to defend against someone who already has the device.


### Echo suppression is a window, not a single shot

Writing the clipboard raises *several* change notifications, not one — pronounced on Android. Suppressing only the first echo meant one inbound clip was recorded four more times locally and each of those was broadcast back to the peer. So `recordApplied` starts a 3-second window during which byte-identical local changes are not emitted.

What that costs: re-copying identical content within 3 seconds does not sync. Nothing is lost — the peer already holds exactly those bytes, so the event would be a no-op even if it went.

### Session ids and `seq`

`seq` is monotonic per source device **within one session**, not forever: it restarts at zero whenever that device's process does. On Android that is constant — the OS freezes and kills apps freely, and OEM battery managers (ColorOS/HANS on Realme and Oppo) are more aggressive still.

So every envelope also carries `session_id`, random per app launch. A receiver tracks the highest `seq` per `(source_device_id, session_id)`; a new session id resets that tracking.

Without it, `(source, seq)` alone cannot distinguish a restarted counter from a replayed event, and either reading is broken:

- treat a lower `seq` as a replay → every clip from a restarted peer is silently dropped until the *receiver* also restarts;
- treat it as a restart → replay protection is gone.

This was a real, observed failure: a phone restart permanently killed phone → Mac sync while the Mac kept running, with both sides reporting a healthy connection.


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

Images take the same path as text: a `ClipImage` inline in one frame, up to **3 MB**. The `.proto` comment anticipates chunking large images through `FileChunk`, but a single frame is both simpler and lower-latency on a LAN, and `LanChannel` already caps a frame at 4 MB — which comfortably covers the 1–2 MB screenshot that is the common case. Images above 3 MB are not synced yet; they get picked up when file transfer lands and brings chunk reassembly with it.

Both platforms normalise to PNG on the wire. macOS converts a TIFF pasteboard (what a Finder copy yields) before sending, so neither device has to understand the other's native format. Android can only *put* an image on the clipboard as a content URI, so received images are staged in the cache and served through a `FileProvider`.

### 5.1 Platform constraints on clipboard access

Two facts about the host platforms shape what clipboard sync can actually promise. Neither is a bug to engineer around.

**Android only lets the focused app read the clipboard.** Since Android 10 (API 29) a background app gets nothing back; Android 12+ also shows a toast on every read. No permission, foreground service, or manifest flag lifts this — the only escapes are an `AccessibilityService` (Play Store policy risk) or the user explicitly sharing. So:

| Direction | Works when |
| --- | --- |
| macOS → Android (inject) | Always. Writing the clipboard is unrestricted. |
| Android → macOS (auto-capture) | While FuseOS is on screen, **or anywhere once FuseOS is the default keyboard**. |
| Android → macOS (background) | Automatic with the keyboard on; otherwise the Share sheet, the Quick Settings tile, or the notification action. |

This is why **explicit send is not a convenience feature on Android — it is the primary background path out of the device**. Three entry points exist, all of them the same trick: something that briefly holds input focus does the clipboard read.

| Entry point | Reaches | Cost to the user |
| --- | --- | --- |
| Share sheet (`ShareActivity`) | content an app chose to share | share → pick FuseOS |
| Quick Settings tile (`ClipTile`) | whatever is on the clipboard | pull down → tap |
| Notification action | whatever is on the clipboard | pull down → tap |

The tile and the notification both launch `CaptureActivity`, an invisible activity whose only job is to be the focused window for a few frames — long enough for `getPrimaryClip()` to be permitted. It reads the clip, hands it to the island, and finishes.

**The island** (`ui/island/ClipIsland.kt`) is a `TYPE_APPLICATION_OVERLAY` capsule that drops from under the status bar: logo on the left, one line of content, tap to send. It is the Android twin of the macOS `ClipIsland` and exists for the same reason — sync is invisible, so without a signal the user cannot tell "it worked" from "it is broken". It draws over other apps because the moment worth confirming is always a moment the user is in *another* app. The window is `FLAG_NOT_FOCUSABLE`, so it never steals focus and correspondingly cannot read the clipboard itself; that is `CaptureActivity`'s job. Without the "Display over other apps" permission the same sends still happen, reported by a toast.

### 5.2 The keyboard, and why FuseOS ships one

The exemption that removes the tap is the **default input method**. `ClipboardService` allows the read when the calling package is the selected IME, and the check is on the package, not on whether the keyboard is currently on screen — so once FuseOS is the keyboard, the whole process may read the clipboard, including the listener `FuseConnectionService` holds open. `OnPrimaryClipChangedListener` starts firing for copies made in any app, and the island is driven straight from it: no tile, no activity, no tap to reach it.

That is the only reason `ime/FuseKeyboardService` exists. It is a plain QWERTY — two layers, three shift states, no autocorrect, no suggestions, no gesture typing — because every feature it grew would be one to maintain forever in service of a permission workaround. Keystrokes go to the `InputConnection` and are neither stored nor sent.

The alternatives were considered and are worse: `AccessibilityService` works but risks Play Store removal, and Shizuku needs the user to re-pair over wireless debugging after every reboot.

### 5.3 A copy is offered, not taken

With auto-capture on, a copy does **not** leave the device by itself. `ClipboardSync.onLocalCopy` hands it to the island, which asks; sending happens on the tap. Not everything a person copies belongs on another machine, and a password manager's clipboard is the obvious case. When there is no overlay permission there is nowhere to ask, so the clip is sent outright — losing the prompt must not lose the sync.

This is the one place Android and macOS deliberately differ: `NSPasteboard` has no such restriction and macOS sends on copy. It is built: `ShareActivity` takes an `ACTION_SEND` of text or an image, brings the connection up if the process was dead, and pushes it to the account's other devices.

A **foreground service** (`FuseConnectionService`) holds the process open so the LAN listener and the `/signal` socket survive backgrounding. It is what makes *receiving* work with the app closed; it does nothing for capture, because no service type lifts the clipboard-read restriction. `BootReceiver` starts it again after a reboot (`BOOT_COMPLETED` is an exemption from the background FGS-start rules), so a restart does not leave the phone unreachable until someone opens the app.

On macOS the equivalent is a **login item** (`LaunchAtLogin`, via `SMAppService`), enabled the first time the user reaches the signed-in app and a toggle in Account thereafter. Both sides exist for the same reason: the first copy after a restart is exactly when the link has to already be up.

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
