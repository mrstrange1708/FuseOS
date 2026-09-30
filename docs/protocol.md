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
5. **Maintain:** the channel is persistent and bidirectional; a `Heartbeat` envelope every 15s (and once as the channel comes up) keeps it alive and times it; loss triggers reconnection with exponential backoff capped at 15s. A channel that has delivered nothing for 45 s (three heartbeats, each echoed at once) is dead — a peer that left the Wi-Fi without a FIN leaves the read blocked and writes still "succeed" into the buffer — so it is closed and redialled. A handshake that has not finished in 10 s is abandoned the same way. A dialer skips a peer that already has a channel, and "Connect now" (the phone's Home, the Mac popover's Connect) dials every unlinked peer at once — the listening side too, since its dialer may be the stuck one; a second channel just replaces the first.

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
    FileCancel file_cancel = 16;
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
| `HEARTBEAT` | either | liveness, and the link's live round trip: a ping is echoed at once (§4) |
| `FILE_CANCEL` | either | this end of a transfer gave up; the other stops and discards |
| `HISTORY_SYNC` | either | recent clipboard history, sent once per new channel (§9) |
| `PHONE_NOTIFICATION` | phone → Mac | a notification posted on the phone (§10) |
| `NOTIFICATION_DISMISS` | either | a mirrored notification went away (§10) |
| `NOTIFICATION_REPLY` | Mac → phone | reply to a mirrored chat or SMS notification (§10) |
| `CALL_STATE` | phone → Mac | a call ringing, in progress, or ended (§10) |
| `CALL_ACTION` | Mac → phone | answer, decline or end the call (§10) |
| `SCREEN_CONTROL` | either | start / stop / keyframe for screen mirroring (§11) |
| `SCREEN_FRAME` | phone → Mac | one H.264 access unit of the phone's screen (§11) |
| `PHONE_COMMAND` | Mac → phone | ring the phone or stop ringing (§12); `TAKE_PHOTO` was removed and its tag is reserved |
| `OPEN_LINK` | either | open an http(s) link on the other device (§12) |
| `MEDIA_STATE` | phone → Mac | what the phone is playing (§13) |
| `MEDIA_COMMAND` | Mac → phone | play/pause, next, previous, seek (§13) |
| `POINTER_INPUT` | phone → Mac | the phone as the Mac's trackpad and keyboard (§14) |
| `SIDECAR_CONTROL` | either | start / stop / keyframe for the phone as a second display (§16) |
| `SIDECAR_FRAME` | Mac → phone | one H.264 access unit of the Mac's extra display (§16) |
| `SIDECAR_INPUT` | phone → Mac | a touch on the second display (§16) |
| `DEVICE_STATUS` | either | battery and charging, live (§17) |
| `BEACON_KEY` | Mac → phone | the key the phone's private Bluetooth beacon rotates with (§15) |
| `UNLOCKED` | either | "my user just unlocked me" (§15) |
| `BEACON_CHECK` | Mac → phone, answered phone → Mac | "Bluetooth hears you far — beacon at full power"; the answer says whether the beacon is on (§15) |
| `NOTIFICATION_OPEN` | Mac → phone | the user clicked a mirrored notification; open it on the phone (§10) |
| `OUTCOME` | either | how something the other device asked for went — a reply, an opened notification, an unlock, a link — with a sentence saying why when it failed (§18) |
| `REMOTE_INPUT` | Mac → phone | a tap, swipe, long-press, Back/Home/Recents, text or key for the phone to perform (§11) |

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

**The ack is how sync speed is measured.** B sends `ACK` with `ref_seq = n` (and no `ref_transfer_id`) once it has applied a clip — never for one the loop guard refused, nor for one that arrived stale (below). A keeps the send time of each unacknowledged clip (monotonic clock, at most 64 outstanding) and, on the ack, records the round trip in a window of the last 50: `SyncLatency { lastMs, p95Ms }`, shown on both apps' link card. A round trip, because the two devices' clocks cannot be trusted to agree to the millisecond; it bounds copy-to-available from above, so a round-trip p95 under the PRD's 300 ms meets the target. An ack is not a clip and is never re-emitted, so it cannot loop; a build that predates it ignores an ack whose transfer id it does not know.

**Heartbeats keep it live.** Clips alone left the number empty until the first copy and stale after it. So every heartbeat is a ping (`echo_seq` 0): the other end answers at once, on that channel only, with `echo_seq` = the ping's `seq`, and the pinger records that round trip in the same window. A ping goes as soon as a channel comes up, then every 15 s — traffic the link already had, so nothing new polls. An echo is never answered, and a build that predates it simply does not echo (its peer keeps at most 16 unanswered pings).

**Only round trips of the link count** (`RoundTrip`, mirrored on both clients). Two things made samples measure something else and pinned the p95 at seconds, or minutes, while clips crossed in 30 ms:

- *A side asleep.* Doze holds a phone app's socket reads until the phone wakes (a sleeping Mac holds its own), so a ping answered then timed the sleep. A ping, echo, clip or ack whose `sent_at_unix_ms` is more than 2 s old on arrival waited in a buffer: it is neither answered (no echo, no `ACK` — the clip itself is still applied) nor timed. The 2 s compares two NTP-synced wall clocks; a larger skew only stops samples, it never produces wrong ones.
- *A queue.* One channel carries images, history, file chunks, Now Playing artwork and screen/Sidecar frames; a heartbeat behind a 2 MB image times the image. Each client notes when a bulk envelope (`CLIP_IMAGE`, `HISTORY_SYNC`, `FILE_CHUNK`, `SCREEN_FRAME`, `SIDECAR_FRAME`, `MEDIA_STATE`) last finished crossing, either way, and drops a round trip that one overlapped. An image clip's own ack is dropped the same way — its time is its size.

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

### 5.2 The copy pop-up (and why FuseOS no longer ships a keyboard)

FuseOS used to ship its own keyboard, because the default input method is the one thing Android exempts from the background clipboard-read block. People keep Gboard, so it went (2026-09-27). Instead, the FuseOS accessibility service (the same one remote control uses, §11) watches for the *moment* of copying — a tap on a control labelled Copy (selection toolbar, a chat's copy icon, "Copy link address") or a "Copied" confirmation from the system or the app (`CopyDetector`, pinned by a test). On that it opens `CaptureActivity` for an instant — focused, so it may read the clipboard — and the island offers the copy: "Copied · tap to send". It stays quiet when the clipboard is empty or holds what it just offered, fires once per copy (a tap and its confirmation within 1.5 s count once), and never for FuseOS's own events. Only control labels are looked at, never window content. The user can switch the pop-up off in Profile.

### 5.3 A copy is offered, not taken

With auto-capture on, a copy does **not** leave the device by itself. `ClipboardSync.onLocalCopy` hands it to the island, which asks; sending happens on the tap. Not everything a person copies belongs on another machine, and a password manager's clipboard is the obvious case. When there is no overlay permission there is nowhere to ask, so the clip is sent outright — losing the prompt must not lose the sync.

This is the one place Android and macOS deliberately differ: `NSPasteboard` has no such restriction and macOS sends on copy. It is built: `ShareActivity` takes an `ACTION_SEND` or `ACTION_SEND_MULTIPLE` of any type and brings the connection up if the process was dead. Text, or a single image within the 3 MB inline cap, goes to the Mac's clipboard as a `ClipText`/`ClipImage`. Anything else (a PDF, a video, a larger photo, several files) goes as a file transfer (§6) into the Mac's Downloads. The activity copies each shared file into app storage first, because a shared `Uri` stays readable only while the activity is alive, and it finishes as soon as the send starts.

The Mac side of the same feature is **Finder Services**, not a Share-sheet extension: a Share extension must be sandboxed and share an App Group with the app, which needs a paid Apple Team ID. Right-click → Services → **Send to Phone with FuseOS** hands the selected files to `AppDelegate.sendFiles`, which runs the §6 transfer. **Send Text to Phone with FuseOS** puts the selected text on the pasteboard, and ordinary clipboard sync sends it. Dropping files onto the menu bar popover sends them too.

A **foreground service** (`FuseConnectionService`) holds the process open so the LAN listener and the `/signal` socket survive backgrounding. It is what makes *receiving* work with the app closed; it does nothing for capture, because no service type lifts the clipboard-read restriction. `BootReceiver` starts it again after a reboot (`BOOT_COMPLETED` is an exemption from the background FGS-start rules), so a restart does not leave the phone unreachable until someone opens the app.

On macOS the equivalent is a **login item** (`LaunchAtLogin`, via `SMAppService`), enabled the first time the user reaches the signed-in app and a toggle in Account thereafter. Both sides exist for the same reason: the first copy after a restart is exactly when the link has to already be up.

**`NSPasteboard` has no change notification.** No observer, no delegate, no notification: the only way to detect a copy on macOS is to poll `changeCount`. `ClipboardSync` does so every 300 ms. This is the one sanctioned exception to the project's "never poll" rule (`CLAUDE.md`), which is about network round trips — this is a local integer read with no I/O behind it.

## 6. File transfer flow

1. Sender emits `FILE_META` (name, size, mime, checksum). The checksum is **sha-256, lowercase hex**, over the whole file — so the sender reads the file twice, once to hash and once to stream. The receiver has to be able to verify *before* it commits the file anywhere, which rules out hashing as it goes.
2. Sender streams ordered `FILE_CHUNK` messages. **64 KB per chunk**, `index` starting at 0 and incrementing by one, `last` set on the final chunk. 64 KB keeps a frame far below `LanChannel`'s 4 MB cap even after protobuf framing and the GCM tag, while keeping a 100 MB file at ~1600 frames.
3. Receiver writes to a hidden partial file, verifies size and checksum on `last`, and only then moves it into place under a **sanitised** name (a peer-supplied name is reduced to its last path component — a name is never a path) that never overwrites an existing file.
4. Receiver emits `ACK` with `ref_transfer_id` on success. The ack is what moves the sender's row from "waiting for the other device to confirm" to "sent": a file is only sent once it has been checked on the other end.
5. **Either end may give up** and emits `FILE_CANCEL` with the `transfer_id` when it does. The sender does this when the user cancels or the file becomes unreadable partway. The receiver does this when the user cancels, a write fails, a chunk arrives out of order or overruns, or the file fails verification. The other end stops and discards. Without it, a cancelled send left the receiver's partial file on disk indefinitely, and a rejected one left the sender waiting for an ack that would never come. A `FILE_CANCEL` for an unknown or finished id is ignored. An older client that predates the message sees an envelope with no body and drops it, so the addition is backward-compatible.
6. Images larger than a single message use the same chunking mechanism.

**Failure is total, and reported.** An out-of-order index, an over-long stream, a write error, or a checksum mismatch abandons the transfer, deletes the partial and tells the sender (`FILE_CANCEL`); a half file is never handed to the user. A peer whose channel drops mid-transfer has its partials discarded at once. With no peer left connected, outgoing transfers fail rather than wait for an ack. A partial left behind by a killed process is swept the next time the app starts. There is **no resume**: a dropped connection means the user re-sends, which on a LAN costs seconds and costs far less code than a resume protocol that would have to survive both ends restarting. A transfer is capped at **1 GiB**, which bounds what one peer can make the other write to disk.

**Chunks must reach the socket in the order they were sealed.** Each frame's counter is its GCM nonce, so a pair that seals in one order and writes in the other fails its tag check and kills the channel. `LanChannel` serialises writes for this reason on both platforms — it went unnoticed while every message was a lone clipboard event, and became load-bearing the moment a heartbeat could land in the middle of a file.

**Receiving applies backpressure; it never drops.** Android's receive loop suspends while its collectors are behind, which stops reading the socket and lets TCP slow the sender down. It used to `tryEmit` into a 64-slot buffer and dropped whatever did not fit. A file chunk dropped that way failed the index check, so every file over about 4 MB failed.

Both clients implement this in `FileTransfer` (`FuseOSCore/FileTransfer.swift`, `com.fuseos.app.file.FileTransfer`) and both test it by driving a sender straight into a receiver. Each reports `TransferProgress` (active → sent → done, or cancelled / failed), throttled to about 1% steps.

- **macOS:** files are sent from a drop zone or an open panel on Home, and a received file lands in `~/Downloads`.
- **Android:** files are sent from the system document picker on Home. A received file is verified in app storage, then moved to the public Downloads collection (API 29+; below that it stays in app storage behind the FileProvider), and a notification opens it.

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
- Heartbeats detect half-open connections and trigger reconnect: 45 s of silence closes the channel (§ Maintain, above).

## 9. History catch-up

A copy made while the devices were apart never reaches the other side, and on Android a copy is only recorded once the user sends it — so without this the two history lists drift apart.

1. Whenever a channel comes up (reconnects included), **each end** sends `HISTORY_SYNC` with its recent history, newest first, up to **3 MB** so one frame stays under `LanChannel`'s 4 MB cap. An image too large for what is left of the budget is skipped, not the rest of the list.
2. The receiver adds each entry it does not already hold — matched by the same content hash `LoopGuard` uses — at its original `at_unix_ms`, re-sorts, and trims to its usual caps.
3. **History only.** The clipboard is not written, the island stays quiet, and a `HISTORY_SYNC` is never answered with another one. That is why it cannot loop, and why it does not pass through `LoopGuard`.
4. **History is per device.** Every entry remembers the peer it crossed with (`source_device_id` for what arrived, the linked peer for what was sent). Each end shows only the entries of the peers linked right now, plus copies made while nothing was linked; with nothing linked, that is all it shows. `HISTORY_SYNC` goes to the joining peer alone and carries only that peer's entries — the unsent copies are handed to it first — so a second phone never receives the first one's clips. Entries stored before this rule have no peer and are dropped on load.

Both clients: `ClipboardSync.sendHistory()` / `merge()` / `publish()`.

## 10. Notification sync

Phone → Mac, while linked.

- **Android** (`notify/NotificationSync.kt`) listens through a `NotificationListenerService` the user enables under *Settings → Notification access*, with an on/off switch in Profile. It forwards a posted notification only when the switch is on and a Mac is linked, and never FuseOS's own, ongoing ones (media, navigation, downloads), group summaries, or ones with no title or text (`NotificationSync.shouldForward`, pinned by a unit test). Nothing is queued: a notification from while the Mac was away is not delivered late. Text is capped at 1,000 characters; the app icon rides along as a 64 px PNG.
- **`key`** is Android's `StatusBarNotification` key. Posting again with the same key replaces the earlier one on the Mac (a chat's next message).
- **macOS** (`NotificationMirror`, `PhoneNotifier`) shows it in the island and files it in Notification Center (list only — the island is the banner), with the key as the request id.
- **Opening.** Clicking a notification in the Mac's island sends `NOTIFICATION_OPEN`; the phone fires that notification's own content intent, as a tap in its shade would (keeping the last 200 by key), with Android's background-start allowance — which FuseOS has only while it holds the overlay permission, so without it the phone answers with a failed `OUTCOME` saying so rather than firing an intent Android would drop. A locked phone opens it behind the lock and says "Unlock your phone to see it".
- **Dismissal runs both ways.** The phone sends `NOTIFICATION_DISMISS` when one is removed there; the Mac removes it. Clearing one in Notification Center on the Mac sends `NOTIFICATION_DISMISS` back and the phone cancels it. The phone remembers keys the Mac cleared, so the removal that causes is not reported back. The phone is the only origin of notifications, so nothing here can loop.
- **Live activities.** An ongoing notification normally stays on the phone — a service's "running in the background" placard is status, not news. But one that is really an activity crosses with `ongoing = true`: it shows a progress bar or a running clock, or its category is navigation, progress, stopwatch, workout or alarm (`NotificationSync.isLiveActivity`, pinned by a test). Media is Now Playing's (§13), not this. Progress rides along (`progress`, `progress_max`, `indeterminate`), updates are throttled to one a second per activity, and the Mac shows them in a *Live on your phone* panel, updated in place and never as a banner or in the island. `NOTIFICATION_DISMISS` removes one when it ends.
- **Replies.** A notification whose app offers an inline reply (chats, SMS) arrives with `can_reply`; on the Mac the island shows it with **Reply**, which turns the island into a text field (the island takes the keyboard without activating FuseOS). Every notification shows in the island — a macOS banner is not relied on, because an unsigned app is often refused notification permission — and Notification Center keeps a list copy when allowed. The typed text goes back as `NOTIFICATION_REPLY`, and the phone fills the app's own reply action with it, as if typed in the shade — so SMS replies need no SMS permission. The phone keeps the last 200 reply actions by key, and answers every reply with an `OUTCOME` — sent, or why not (the notification is gone, the app refused it). The reply field cancels on Esc, its ✕, a click anywhere else, or 20 s untouched and empty; it never holds the island open for good.
- **Calls.** The dialer's call notification (`CATEGORY_CALL`) is mirrored as `CALL_STATE`, never as a notification: `RINGING`, `ACTIVE` once it shows a running timer, `ENDED` when it goes. The Mac's island shows it — Answer and Decline while ringing (and stays up), End once answered. `CALL_ACTION` is carried out through the telecom service when the user granted *Calls on your Mac* (`ANSWER_PHONE_CALLS`); 1.5 s later the phone checks the call actually changed (answered shows a running timer, declined or ended removes the notification), because an OEM dialer can ignore telecom without an error, and if not it presses the call notification's own button whose label says answer/decline/end. The Mac hears the result as an `OUTCOME` of kind `CALL`. Call audio stays on the phone — the Mac is not a Bluetooth headset — so answering from the Mac turns the phone's speaker on.
- **One-time codes.** When a notification's text reads like a code (`OneTimeCode`: a 4–8 digit run, or `123-456`, near words like OTP / code / verify / sign in, never a currency amount), the island swaps Reply for **Copy 482913** and, with Accessibility allowed, **Paste** — which types ⌘V into the app you are in (the island never takes focus, so that is the field the code is for). The code goes on the Mac's clipboard only (`copyLocally`): not back to the phone, not into the history. Detection is on the Mac, from the text that already crossed; nothing new travels.
- Notification text is user payload: LAN-only and encrypted like the clipboard, never logged, never in analytics.

## 11. Screen mirroring

Phone → Mac, with remote control when the user allows it.

1. Either end starts it. The Mac sends `SCREEN_CONTROL START`; the phone opens Android's capture-consent dialog (directly when it holds the overlay permission, which exempts it from the background-activity-launch block; otherwise through a notification). Or the user taps *Share screen* on the phone. Android asks for consent every session.
2. On consent the phone starts a `mediaProjection` foreground service, sends `SCREEN_CONTROL START`, and streams: a virtual display draws into a hardware H.264 encoder's input surface, and each encoded access unit goes out as a `SCREEN_FRAME` (Annex-B) on the **same encrypted channel** as everything else. Realtime priority, 30 fps, 6 Mbit/s, long side ≤ 1600 px, a keyframe every 2 s with SPS/PPS prepended, and the last frame repeated after 100 ms of stillness so the Mac never waits on a static screen.
3. The Mac reframes Annex-B to AVCC, builds the format from the SPS/PPS, and enqueues each sample on an `AVSampleBufferDisplayLayer` marked *display immediately* — hardware decode, no decoder session of our own. A decode failure flushes the layer and sends `SCREEN_CONTROL KEYFRAME`.
4. **Rotation** swaps in a new encoder at the new size and resizes the same virtual display (Android 14 allows one per projection). The new encoder's parameter sets tell the Mac the new shape; the Mac rebuilds its format from any frame carrying SPS/PPS and flushes the layer when the shape changes.
5. `SCREEN_CONTROL STOP` from either end ends it; the phone also stops when its user ends it from the system chip or notification, or when no Mac is linked any more. A refused consent sends `STOP`, so the Mac does not wait forever.

**Remote control.** With the phone's *FuseOS remote control* accessibility service on (Settings → Accessibility; a Profile row links there), the phone's `SCREEN_CONTROL START` carries `remote_control = true` and the Mac turns its mirror interactive: a click is a `TAP`, a hold over 0.5 s a `LONG_PRESS`, a drag a `SWIPE` (its real duration, clamped to 60 ms–2 s), wheel/trackpad scrolling a `SWIPE` gathered over 80 ms, typing `TEXT` into the focused field, Delete and Return `KEY` 67/66, and Esc `BACK`; buttons send `BACK`, `HOME` and `RECENTS`. Positions are 0–1 of the mirrored image, top-left origin — the aspect-fit mirror keeps that equal to the phone's screen. The phone performs them with `dispatchGesture`, global actions, and `ACTION_SET_TEXT` on the focused editable node — the one piece of other apps' UI it reads. **The phone drops every `REMOTE_INPUT` unless it is sharing its screen at that moment**, so control never outlives the consent the user gave to be seen. The service is possible because FuseOS ships as an APK, not through Google Play.

Sharing the channel means a burst of video can delay a clipboard frame behind it on the same TCP stream. At these bitrates on a LAN that is milliseconds; a separate channel is the fix if measurement ever says otherwise.

## 12. Phone actions and Handoff

Small commands, each one message on the LAN channel; none touches the server.

- **Ring** (`PHONE_COMMAND RING`) — the phone plays its alarm sound on the alarm stream at full volume, so silent mode does not mute it, and shows an ongoing notification with Stop. It stops on `STOP_RING`, on that Stop, or after 30 s, and puts the alarm volume back.
- **Take photo** was removed on 2026-09-28 (the user wanted the phone as a live webcam, which needs a camera system extension and so a paid Apple Team ID). `TAKE_PHOTO` (3) stays reserved in the proto.
- **Open a link** (`OPEN_LINK`) — Handoff. Phone → Mac through *Open on Mac* in the Android Share sheet; Mac → phone through *Open Link on Phone with FuseOS* in the Services menu or *Open copied link* on Home. The receiver opens **http and https only**; any other scheme is dropped, so a peer cannot make the other device launch arbitrary intents or URL handlers.

Anything the phone must show while FuseOS is in the background (a link, a consent dialog) opens directly when FuseOS holds the overlay permission, which exempts it from Android's background-activity-launch block, and through a tap-to-open notification otherwise.

## 13. Now Playing

- **Phone** (`notify/MediaSync.kt`) — other apps' media sessions are readable only by an enabled notification listener, which FuseOS already is for notification sync, so Now Playing starts when that listener connects. It follows the session that is playing, else the most recent, and sends `MEDIA_STATE` when its track or play state changes and whenever a Mac connects; `active = false` when nothing is playing. Position is carried to the send time (`position_ms` at `position_at_unix_ms`), and artwork (a 256 px JPEG) only with a new track.
- **Mac** (`MediaRemote`, `NowPlaying`) — shows a Now Playing panel on Home and advances the bar itself from the wall clock while playing, so position-only updates never cross the wire. Its buttons send `MEDIA_COMMAND` (`PLAY_PAUSE`, `NEXT`, `PREVIOUS`, `SEEK`), which the phone applies to the session's transport controls. The panel goes when the phone does.

## 14. The phone as the Mac's trackpad and keyboard

*Use as trackpad* on the phone's Screen tab opens a full-screen pad: one finger sends `MOVE` deltas (scaled 1.6×), a tap `CLICK`, a second tap within 320 ms `DOUBLE_CLICK`, a two-finger tap `RIGHT_CLICK`, two fingers `SCROLL`, and a still hold of 420 ms turns into `DRAG_START` … `DRAG_END`. Three fingers are a gesture, sent once on release as the Mac's own shortcut — left/right `KEY` ⌃→/⌃← (switch desktops), up ⌃↑ (Mission Control), down ⌃↓ (App Exposé) — for a movement of at least 120 px. A text field below types `TEXT` into whatever has focus on the Mac (it holds one sentinel space, so a backspace on an "empty" field still arrives, as `KEY` 51; suggestions and autocorrect are off, since they rewrite words a keystroke-forwarding field has already sent; the keyboard's Send is Return), and a key row sends Esc, Tab, the arrows and Return as Mac virtual key codes.

The phone is told which way the gates stand before it sends anything: the Mac's `DEVICE_STATUS` carries `pointer_allowed`, re-sent when the switch flips or macOS's Accessibility list changes (`com.apple.accessibility.api`). While it is false the phone's trackpad shows *Turned off on your Mac* and what to turn on, instead of sending input into nothing; input that arrives anyway gets a once-a-minute island on the Mac naming the missing gate.

The Mac acts on `POINTER_INPUT` only when **both** gates are open: the user's *Let your phone control this Mac* switch in Account (off by default), and macOS Accessibility access for FuseOS (turning the switch on asks macOS to show its prompt). It then posts real `CGEvent`s — mouse moves clamped to the screens, clicks with the right click count, pixel scroll-wheel events, and Unicode keyboard events for text.

## 15. Nearby lock and unlock

**Distance.** Wi-Fi cannot tell distance, so the phone runs a private Bluetooth beacon: low power, not connectable, manufacturer data (company id 0xFFFF) = `HMAC-SHA256(key, window)[0..8]`, where the window is unix time in ten-minute steps as an 8-byte big-endian integer (`BeaconToken`; a shared test vector pins both platforms). The Mac sends a fresh random 16-byte key in `BEACON_KEY` on every channel, so nobody without it can recognise or follow the phone, and the value changes every ten minutes. The Mac scans (CoreBluetooth), accepts this or the previous window's value, and keeps a smoothed RSSI: near at −72 dBm or stronger, far at −88 or weaker (a gap, so it does not flap), and far after 25 s without hearing it.

**Lock.** With *Lock this Mac when your phone leaves* on (off by default), Bluetooth and Wi-Fi must agree (`AwayLock.shouldLock`, pinned by tests). Bluetooth is the only signal that measures distance, but Android throttles a background beacon, so a phone lying next to the Mac can go quiet or read weak; Wi-Fi measures nothing, but it is steady. So:

- **Still linked over Wi-Fi** when Bluetooth turns far: the Mac sends `BEACON_CHECK` over the link, the phone beacons at full power (low-latency mode, high TX) for 20 s and answers with `BEACON_CHECK` saying whether its beacon is on. After 15 s the Mac locks only if the beacon is on and it *still* hears the phone far or not at all. A throttled beacon next to the Mac comes back near, which cancels the lock. A phone whose beacon is off (Bluetooth off, refused by Android) gives no distance, so it never locks.
- **Link down:** checked 20 s after the channel drops (and 10 s after Bluetooth turns far). It locks only if the phone is online via `/signal` on **another network** — its presence `lan_address` is not on the Mac's /24 — because leaving the Wi-Fi is itself a sign it left. On this Wi-Fi with the link down, the app was often paused next to the Mac, and nothing can check it, so it does not lock; a phone gone quiet everywhere (asleep, killed, battery dead) never locks either.
- A link that comes back while Bluetooth still says far runs the check again.

Skipped locks are logged under `com.fuseos.app` / `unlock` with what each signal said.

**The key survives restarts.** Both sides keep the latest `BEACON_KEY` on disk. Before that, a phone whose process was killed, or a Mac that relaunched, had no key until the next channel, so the beacon was silent or unrecognised and lock and unlock did nothing. The phone beacons as soon as it starts, restarts the beacon when Bluetooth comes back, and shows in Profile what the beacon is doing: broadcasting, Bluetooth off, waiting for the Mac's key, or refused by Android (with its error code). The lock is the same as ⌃⌘Q (`SACLockScreenImmediate`, private, looked up at run time).

**Unlock — experimental, opt-in.** macOS has no API for a third party to unlock the screen. With *Unlock this Mac with your phone* on, the Mac asks once for the login password, checks it against Open Directory, and keeps it in the login Keychain (this device only). When the phone is unlocked it sends `UNLOCKED`; if the Mac's screen is locked and the phone is **near** by Bluetooth, the Mac wakes the display and types the password at the lock screen (needs Accessibility; a macOS that blocks synthetic input there will refuse it). When the Mac is unlocked it sends `UNLOCKED`, and the phone wakes its screen — an app cannot get past Android's own lock.

A phone that was locked has often lost its LAN link; it holds `UNLOCKED` for up to 10 s and sends it when the link returns. Every refusal is said, not just logged: when the Mac is locked and the feature is on, it answers `UNLOCKED` with an `OUTCOME` — unlocked, or why not (not near by Bluetooth, and why it can't hear the phone; no Accessibility grant; no stored password; macOS refused the typed password, judged by the screen still being locked 2.5 s later) — and the phone's island says it. The Account pane shows a live line under both switches: whether the phone is close, or what stops the Mac hearing it (Bluetooth off or not allowed, beacon not heard). Refusals are also logged under `com.fuseos.app` / `unlock` — `log stream --predicate 'subsystem == "com.fuseos.app" && category == "unlock"'`.

## 16. Sidecar — the phone as a second display

The reverse of mirroring (§11): the Mac draws, the phone shows.

1. *Use as a second display* on the phone's Screen tab opens a full-screen landscape view and sends `SIDECAR_CONTROL START` with its size in pixels and its density.
2. The Mac adds a display of that shape — a CoreGraphics virtual display (`CGVirtualDisplay`, declared in the small `VirtualDisplay` target because it has no public header), HiDPI so it is sharp, capped at a 2400 px long side — captures it with ScreenCaptureKit at 30 fps, and encodes it with VideoToolbox: H.264 Main, realtime, no B-frames, 8 Mbit/s, a keyframe every 2 s, SPS/PPS ahead of every keyframe. Each access unit goes out Annex-B as `SIDECAR_FRAME` (a `ScreenFrame` on its own field). ScreenCaptureKit sends only changed frames, so a still display costs nothing. The Mac answers `START` once frames flow — or `STOP` if it cannot (Screen Recording not granted), so the phone is not left waiting.
3. The phone decodes with MediaCodec straight onto a SurfaceView, starting at the first keyframe. If its queue backs up it drops the backlog and sends `KEYFRAME` to rejoin cleanly.
4. Touches come back as `SIDECAR_INPUT` at 0–1 of the display: a tap clicks, a drag is `DOWN`/`MOVE`/`UP`, two fingers `SCROLL`, a long press `RIGHT_CLICK`. The Mac maps them onto the virtual display's bounds and posts real mouse events — only with Accessibility access, as for §14.
5. Leaving the phone's screen sends `STOP`; the Mac stops capture and releases the display, which removes it. A dropped link removes it too.

## 17. Battery and charging

Each device sends `DEVICE_STATUS` (battery 0–100, or -1 with no battery; charging) when a channel comes up and whenever it changes — Android from the system's sticky battery broadcast, macOS from IOKit's power-source notification; neither polls. The Mac shows the phone's with a bolt while charging (link card and menu bar ring); the phone shows the Mac's on its link card. The server's presence battery stays the fallback when there is no channel.

## 18. Outcomes — nothing fails silently

A request that crosses the link can fail on the far side, where the asker cannot see it. `OUTCOME` closes that loop: the device that was asked answers with `kind` (`REPLY`, `OPEN_NOTIFICATION`, `UNLOCK`, `OPEN_LINK`, `CALL`), `ok`, and `detail` — a short sentence for a person, shown as-is, that names the fix when there is one. The asker says it in its island (red for a failure, held long enough to read). Everything else that can fail is said locally the same way — both islands are the single place outcomes appear, and on Android a missing overlay permission falls back to a toast rather than to silence. An outcome is only ever sent in answer to a request, so it cannot loop, and it carries no user payload beyond what the request already did.
