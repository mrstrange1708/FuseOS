# clients/android — FuseOS Android app

Kotlin + Jetpack Compose. Implements the **login / sign-up flow** (Slice 01): sign in, create account, and a signed-in home screen with a "this device" card. Talks to the FuseOS control-plane auth API.

## Stack
- Jetpack Compose + Material 3, MVVM (`AuthViewModel` + `AuthRepository`)
- Ktor client (OkHttp engine) + kotlinx.serialization for the API
- DataStore for session persistence
- Manual DI via `ServiceLocator`

## Run

Prereqs: **JDK 17** and the **Android SDK** (Android Studio, or `ANDROID_HOME` set). `local.properties` (git-ignored) must point `sdk.dir` at your SDK.

### When `adb devices` is empty
Two failures look identical from the outside — the pane just sits there:

- **adb itself never started.** On macOS 26 its mDNS discovery fails to bind and takes the whole server down with `could not install *smartsocket* listener: Address already in use`, even though nothing holds port 5037. `export ADB_MDNS=0` fixes it; the mprocs panes already do. Check with `ADB_MDNS=0 adb start-server`.
- **The phone isn't offering an ADB interface.** `ADB_TRACE=1 adb nodaemon server` says `ignoring device usb:N-N: not an adb interface` — the cable and the USB enumeration are fine, but USB debugging is off. On the phone: Settings → About → tap the build number until Developer options unlock, then Developer options → **USB debugging** on, and set the USB mode to **File transfer**, not charge-only. Accept the "Allow USB debugging?" prompt when it appears.

From the repo root, `pnpm start` brings up the server, the macOS app, and this app on an attached phone as mprocs panes (`android` is this one; `r` reinstalls). To drive Gradle directly:

1. Start the server: from the repo root, `pnpm --filter server dev` (listens on `:3000`).
2. Build the debug APK:
   ```bash
   ./gradlew :app:assembleDebug
   # → app/build/outputs/apk/debug/app-debug.apk
   ```
3. Install/run: open the folder in Android Studio and Run on an emulator, or `./gradlew installDebug` with a device/emulator attached.

### Pointing at the server
The URL is baked in at build time from the `serverUrl` Gradle property (`BuildConfig.SERVER_URL`, read by `core/Config.kt`).

- **Physical device**: the `android` pane in `pnpm start` runs `adb reverse tcp:3000 tcp:3000` and installs with `http://127.0.0.1:3000`, so the control plane goes over the USB cable — no LAN IP to go stale, and no dependency on a Wi-Fi that lets its clients talk to each other (hotspots, campus and cafe networks usually don't). By hand: the same two commands. If you'd rather go over Wi-Fi, `./gradlew installDebug -PserverUrl=http://<mac-lan-ip>:3000` still works.
- **Emulator**: the default, `http://10.0.2.2:3000` — the emulator's alias for the host's localhost. No property needed.

Note this is the **control plane** only. Clipboard and file transfer are peer-to-peer over the LAN, so both devices still have to be on the same Wi-Fi for those.

Cleartext to LAN hosts is already allowed for dev via `network_security_config.xml`.

### Pairing
Three ways in, from the "Connect a device" sheet: **Scan QR** (the default — points the camera at the QR the Mac shows), **Enter code** (eight boxes, `XXXX-XXXX`, lowercase auto-uppercases, pairs on the last character), and **Show code** for the other direction. The camera permission is requested when the scanner opens; deny it and typing the code still works.

## What works
Sign up → lands on the dashboard; sign in with the same credentials; validation (email format, 8-char password) and server error messages surface inline; sign out clears the session.

The dashboard shows this device, every paired device with live presence, battery and whether there is a direct LAN channel (`connected · direct`), and the **clipboard history** — the last 50 items copied here or received from a peer, newest first, each tagged with where it came from. Tap one to put it back on the clipboard. The history is in memory only: clipboard content is never written to disk, and never leaves the LAN.

Peers connect on their own — there is no "connect" button beyond pairing. `LanTransport` dials whatever `/signal` reports as online.
