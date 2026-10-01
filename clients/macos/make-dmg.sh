#!/usr/bin/env bash
# Packs a release build into .build/FuseOS.dmg: the app next to an Applications link,
# so installing is one drag.
#
# ponytail: self-signed (see build-app.sh) and not notarized — there is no paid Developer ID. On first
# launch macOS blocks it; the user opens it once, then System Settings → Privacy &
# Security → Open Anyway. The website's install steps say so.
set -euo pipefail
cd "$(dirname "$0")"

./build-app.sh release

# The window it opens into: the app, an arrow, Applications, and "Read Me First" with every
# permission to switch on (dmg/). dmgbuild writes Finder's layout itself — no AppleScript, so it
# works on CI. It lives in its own venv; nothing is installed system-wide.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
textutil -convert rtf dmg/ReadMe.html -output "$STAGE/Read Me First.rtf"
[ -x .build/dmgenv/bin/dmgbuild ] || {
	python3 -m venv .build/dmgenv
	.build/dmgenv/bin/pip install -q dmgbuild==1.6.7
}

rm -f .build/FuseOS.dmg
.build/dmgenv/bin/dmgbuild -s dmg/settings.py \
	-D app=.build/FuseOS.app -D readme="$STAGE/Read Me First.rtf" -D background=dmg/background.tiff \
	FuseOS .build/FuseOS.dmg >/dev/null
echo "built .build/FuseOS.dmg ($(du -h .build/FuseOS.dmg | cut -f1))"
