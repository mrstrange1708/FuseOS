# clients/macos — FuseOS macOS app

SwiftUI. Implements the **login / sign-up flow** (Slice 01): sign in, create account, and a signed-in home screen with a "this device" card. Talks to the FuseOS control-plane auth API.

Built with SwiftPM (no hand-written Xcode project) and assembled into a real `.app` bundle by `build-app.sh`.

## Stack
- SwiftUI, MVVM (`AuthViewModel` + `AuthRepository`, `ObservableObject`)
- `URLSession` async/await + `Codable` for the API
- `UserDefaults`-backed `SessionStore`
- Appearance-aware theme (`FuseColor`, light/dark)

## Run

Prereqs: **Xcode / Swift toolchain** (macOS 13+).

From the repo root, `pnpm start` brings up the server, this app, and the Android app as mprocs panes (`mac` is this one; `r` rebuilds and relaunches). To build this app on its own:

1. Start the server: from the repo root, `pnpm --filter server dev` (listens on `:3000`).
2. Build & run:
   ```bash
   ./build-app.sh              # compile + assemble .build/FuseOS.app
   open .build/FuseOS.app
   ```
   Or open `Package.swift` in Xcode (File ▸ Open) and Run.

**Run the bundle, not `swift run`.** From macOS 15 on, connecting directly to a device on
the LAN needs local-network permission, which is keyed to a bundle identifier — a bare
`swift run` executable has none and gets denied. The unbundled binary also launches as an
accessory process that never comes to the front, so its window ignores clicks.

The bundle is ad-hoc signed (no Developer ID on this machine), so its signature changes on
every build and macOS re-asks for local-network permission after a rebuild. Harmless in
dev; sign with a real identity to make the grant stick.

### Pointing at the server
Default `Config.baseURL = http://localhost:3000` (in `Sources/FuseOS/Networking.swift`),
which assumes the server runs on this Mac. Cleartext to the LAN is allowed via
`NSAllowsLocalNetworking` in `Resources/Info.plist` — remove it once the server is https.

### Pairing
"Connect a device" generates a code and shows it as a **QR** (CoreImage, no dependency) above the same code in eight boxes — the phone scans the QR, or you read the code off it. "Enter a code" is the same eight boxes as an input: lowercase auto-uppercases and it pairs on the last character. The QR keeps a white backing in dark mode so it still scans.

## What works
Sign up → lands on the home screen; sign in with the same credentials; validation (email format, 8-char password) and server error messages surface inline; sign out clears the session. Device pairing / connection is the next slice.
