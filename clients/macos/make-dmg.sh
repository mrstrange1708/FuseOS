#!/usr/bin/env bash
# Packs a release build into .build/FuseOS.dmg: the app next to an Applications link,
# so installing is one drag.
#
# ponytail: ad-hoc signed and not notarized — there is no paid Developer ID. On first
# launch macOS blocks it; the user opens it once, then System Settings → Privacy &
# Security → Open Anyway. The website's install steps say so.
set -euo pipefail
cd "$(dirname "$0")"

./build-app.sh release

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R .build/FuseOS.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f .build/FuseOS.dmg
hdiutil create -volname FuseOS -srcfolder "$STAGE" -format UDZO -ov .build/FuseOS.dmg >/dev/null
echo "built .build/FuseOS.dmg ($(du -h .build/FuseOS.dmg | cut -f1))"
