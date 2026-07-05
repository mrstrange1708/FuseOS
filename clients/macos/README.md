# clients/macos — FuseOS macOS app

SwiftUI. Implements the **login / sign-up flow** (Slice 01): sign in, create account, and a signed-in home screen with a "this device" card. Talks to the FuseOS control-plane auth API.

Packaged as a Swift Package executable so it builds without a hand-written Xcode project.

## Stack
- SwiftUI, MVVM (`AuthViewModel` + `AuthRepository`, `ObservableObject`)
- `URLSession` async/await + `Codable` for the API
- `UserDefaults`-backed `SessionStore`
- Appearance-aware theme (`FuseColor`, light/dark)

## Run

Prereqs: **Xcode / Swift toolchain** (macOS 13+).

1. Start the server: from the repo root, `pnpm --filter server dev` (listens on `:3000`).
2. Build & run:
   ```bash
   swift build          # compile
   swift run            # launch the app
   ```
   Or open `Package.swift` in Xcode (File ▸ Open) and Run — best for the full app experience.

### Pointing at the server
Default `Config.baseURL = http://localhost:3000` (in `Sources/FuseOS/Networking.swift`). If App Transport Security blocks cleartext localhost in your setup, run via Xcode with an ATS exception, or point at an `https` server.

## What works
Sign up → lands on the home screen; sign in with the same credentials; validation (email format, 8-char password) and server error messages surface inline; sign out clears the session. Device pairing / connection is the next slice.
