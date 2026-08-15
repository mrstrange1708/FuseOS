# clients/android — FuseOS Android app

Kotlin + Jetpack Compose. Implements the **login / sign-up flow** (Slice 01): sign in, create account, and a signed-in home screen with a "this device" card. Talks to the FuseOS control-plane auth API.

## Stack
- Jetpack Compose + Material 3, MVVM (`AuthViewModel` + `AuthRepository`)
- Ktor client (OkHttp engine) + kotlinx.serialization for the API
- DataStore for session persistence
- Manual DI via `ServiceLocator`

## Run

Prereqs: **JDK 17** and the **Android SDK** (Android Studio, or `ANDROID_HOME` set). `local.properties` (git-ignored) must point `sdk.dir` at your SDK.

From the repo root, `pnpm start` brings up the server, the macOS app, and this app on an attached phone as mprocs panes (`android` is this one; `r` reinstalls). To drive Gradle directly:

1. Start the server: from the repo root, `pnpm --filter server dev` (listens on `:3000`).
2. Build the debug APK:
   ```bash
   ./gradlew :app:assembleDebug
   # → app/build/outputs/apk/debug/app-debug.apk
   ```
3. Install/run: open the folder in Android Studio and Run on an emulator, or `./gradlew installDebug` with a device/emulator attached.

### Pointing at the server
The URL is baked in at build time from the `serverUrl` Gradle property (`BuildConfig.SERVER_URL`, read by `core/Config.kt`) — no code edit when your Wi-Fi address changes.

- **Physical device**: the `android` pane in `pnpm start` detects this Mac's LAN IP and passes it. By hand: `./gradlew installDebug -PserverUrl=http://192.168.1.20:3000`, phone on the same Wi-Fi.
- **Emulator**: the default, `http://10.0.2.2:3000` — the emulator's alias for the host's localhost. No property needed.

Cleartext to LAN hosts is already allowed for dev via `network_security_config.xml`.

### Pairing
Three ways in, from the "Connect a device" sheet: **Scan QR** (the default — points the camera at the QR the Mac shows), **Enter code** (eight boxes, `XXXX-XXXX`, lowercase auto-uppercases, pairs on the last character), and **Show code** for the other direction. The camera permission is requested when the scanner opens; deny it and typing the code still works.

## What works
Sign up → lands on the home screen; sign in with the same credentials; validation (email format, 8-char password) and server error messages surface inline; sign out clears the session. Device pairing / connection is the next slice.
