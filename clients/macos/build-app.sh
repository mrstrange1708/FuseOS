#!/usr/bin/env bash
# Assembles the SPM executable into a real FuseOS.app bundle.
#
# Why this exists rather than an .xcodeproj: macOS 15+ gates direct LAN connections
# behind a permission prompt keyed to a bundle identifier, and a bare `swift run`
# binary has none — it inherits Terminal's grant at best. The data plane needs a real
# bundle. Keeping SPM (instead of generating a project) keeps `swift build` and the
# swift-protobuf build plugin working.
#
# Usage: ./build-app.sh [debug|release]   →  .build/FuseOS.app
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-debug}"
APP=".build/FuseOS.app"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/FuseOS"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/FuseOS"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# ponytail: ad-hoc signature — there is no Developer ID on this machine. The cdhash
# changes every build, so macOS re-asks for local-network permission after a rebuild.
# Sign with a real identity (or a self-signed cert in the login keychain) to make the
# grant stick.
codesign --force --sign - "$APP"

echo "built $APP — open it with: open $APP"
