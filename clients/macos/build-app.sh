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
GEN="Sources/FuseOSCore/Generated"

# Regenerate the device-to-device bindings from the shared contract. Android does the
# same via protobuf-gradle-plugin; both platforms read ../../proto verbatim.
if ! command -v protoc >/dev/null || ! command -v protoc-gen-swift >/dev/null; then
	echo "need protoc and protoc-gen-swift: brew install protobuf swift-protobuf" >&2
	exit 1
fi
mkdir -p "$GEN"
protoc --swift_out="$GEN" --proto_path=../../proto ../../proto/fuseos.proto

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
