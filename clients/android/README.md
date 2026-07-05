# clients/android — FuseOS Android app

Kotlin + Jetpack Compose. Implements the **login / sign-up flow** (Slice 01): sign in, create account, and a signed-in home screen with a "this device" card. Talks to the FuseOS control-plane auth API.

## Stack
- Jetpack Compose + Material 3, MVVM (`AuthViewModel` + `AuthRepository`)
- Ktor client (OkHttp engine) + kotlinx.serialization for the API
- DataStore for session persistence
- Manual DI via `ServiceLocator`

## Run

Prereqs: **JDK 17** and the **Android SDK** (Android Studio, or `ANDROID_HOME` set). `local.properties` (git-ignored) must point `sdk.dir` at your SDK.

1. Start the server: from the repo root, `pnpm --filter server dev` (listens on `:3000`).
2. Build the debug APK:
   ```bash
   ./gradlew :app:assembleDebug
   # → app/build/outputs/apk/debug/app-debug.apk
   ```
3. Install/run: open the folder in Android Studio and Run on an emulator, or `./gradlew installDebug` with a device/emulator attached.

### Pointing at the server
- **Emulator** (default): `Config.BASE_URL = http://10.0.2.2:3000` — the emulator's alias for the host's localhost. No change needed.
- **Physical device**: set `Config.BASE_URL` (in `core/Config.kt`) to your Mac's LAN IP, e.g. `http://192.168.1.20:3000`, with the phone on the same Wi-Fi. Cleartext to LAN hosts is already allowed for dev via `network_security_config.xml`.

## What works
Sign up → lands on the home screen; sign in with the same credentials; validation (email format, 8-char password) and server error messages surface inline; sign out clears the session. Device pairing / connection is the next slice.
