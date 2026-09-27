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

# Command Line Tools without Xcode ship the macOS 27 SDK, whose SwiftUI expands @State
# through a compiler plugin the CLT do not include — every view fails to build. The 26
# SDK the CLT also ship predates that, so fall back to it. Xcode has the plugin and is
# left alone, as is an SDKROOT set by hand.
PLUGINS="$(xcode-select -p)/usr/lib/swift/host/plugins"
if [ -z "${SDKROOT:-}" ] && [ -d "$PLUGINS" ] && [ ! -e "$PLUGINS/libSwiftUIMacros.dylib" ]; then
	FALLBACK="$(xcode-select -p)/SDKs/MacOSX26.sdk"
	if [ -d "$FALLBACK" ]; then
		export SDKROOT="$FALLBACK"
		echo "no SwiftUI macro plugin in $(xcode-select -p); building against $FALLBACK"
	fi
fi

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/FuseOS"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/FuseOS"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# The icon is committed rather than generated here: it changes about never, and a build
# should not need Pillow. Regenerate with `python3 make-icon.py` after changing the mark.
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Sign with one self-signed identity that lives in its own keychain and is made on the
# first build. The signature then names that certificate rather than this build's hash,
# so macOS keeps Accessibility, Bluetooth and local-network grants across rebuilds —
# with an ad-hoc signature every rebuild silently voided them (the switch in System
# Settings stays on, the app is no longer trusted). No Apple account involved: the
# certificate is not trusted by anyone, it only has to stay the same.
# ponytail: the keychain password is fixed; it guards a local dev identity, not a secret.
SIGN_NAME="FuseOS Local Signing"
SIGN_DIR="$HOME/.fuseos"
SIGN_KC="$SIGN_DIR/signing.keychain-db"
SIGN_PASS="fuseos-local"
if [ ! -f "$SIGN_KC" ]; then
	mkdir -p "$SIGN_DIR"
	TMP="$(mktemp -d)"
	openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$SIGN_NAME" \
		-addext "basicConstraints=critical,CA:false" -addext "keyUsage=critical,digitalSignature" \
		-addext "extendedKeyUsage=critical,codeSigning" -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
	openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" -passout pass:"$SIGN_PASS" 2>/dev/null ||
		openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" -passout pass:"$SIGN_PASS"
	security create-keychain -p "$SIGN_PASS" "$SIGN_KC"
	security set-keychain-settings "$SIGN_KC" # no auto-lock
	security unlock-keychain -p "$SIGN_PASS" "$SIGN_KC"
	security import "$TMP/id.p12" -k "$SIGN_KC" -P "$SIGN_PASS" -T /usr/bin/codesign >/dev/null
	security set-key-partition-list -S apple-tool:,apple: -s -k "$SIGN_PASS" "$SIGN_KC" >/dev/null
	rm -rf "$TMP"
	echo "made signing identity \"$SIGN_NAME\" in $SIGN_KC — grant permissions once more, then they stick"
fi
security unlock-keychain -p "$SIGN_PASS" "$SIGN_KC"
codesign --force --keychain "$SIGN_KC" --sign "$SIGN_NAME" "$APP"

echo "built $APP — open it with: open $APP"
