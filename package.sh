#!/bin/bash
# Builds a universal Hurakai.app and wraps it in a drag-to-install disk image.
#
# ponytail: hdiutil ships with macOS — no create-dmg, no node, no Homebrew. A .dmg
# (drag to Applications) rather than a .pkg: a .pkg installer earns its keep when you
# need scripts, receipts or files outside /Applications, and this app needs none of that.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh --universal

# Read the version from the bundle we just built, so it can't drift from Info.plist.
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    build/Hurakai.app/Contents/Info.plist)"
DMG="dist/Hurakai-$VERSION.dmg"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -R build/Hurakai.app "$STAGE/Hurakai.app"
ln -s /Applications "$STAGE/Applications"

# The app is ad-hoc signed, not notarised, so first launch needs the right-click dance.
# Saying so on the disk image beats a confused "app is damaged" alert.
cat > "$STAGE/READ ME - First Launch.txt" <<'TXT'
Hurakai — Pacific cyclone tracker

INSTALL
  Drag Hurakai onto the Applications folder in this window.

FIRST LAUNCH
  This app is not notarised by Apple, so the first time you open it macOS
  blocks it and says it "could not verify that this app is free of malware".
  That is expected for any app distributed outside the App Store without a
  paid Apple Developer ID. Nothing is wrong with the app.

  On macOS 15 and later, Control-clicking and choosing Open no longer gets
  past this -- Apple removed that shortcut. Do one of these instead:

    1. Double-click Hurakai and let it be blocked. Then open
       System Settings > Privacy & Security, scroll down to Security, and
       click "Open Anyway" next to the message about Hurakai.

    2. Or run this in Terminal to clear the download quarantine flag:

           xattr -dr com.apple.quarantine /Applications/Hurakai.app

  Either way it is a one-time step. After that it opens normally.

  On macOS 14, Control-click > Open > Open still works.

WHAT IT NEEDS
  macOS 14 or later, and a network connection — every forecast, model and
  image is fetched live from NOAA/NWS, NESDIS and NASA GIBS.

Data courtesy NOAA/NWS National Hurricane Center, Central Pacific Hurricane
Center, and NOAA NESDIS. Not an official forecast product — for warnings and
protective decisions use hurricanes.gov and your local NWS office.
TXT

mkdir -p dist
rm -f "$DMG"
hdiutil create \
    -volname "Hurakai $VERSION" \
    -srcfolder "$STAGE" \
    -format UDZO \
    -ov \
    "$DMG" >/dev/null

echo "Built $DMG ($(du -h "$DMG" | cut -f1))"
