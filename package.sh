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
  This app is not notarised by Apple, so macOS will refuse to open it the
  normal way. The first time only:

      Right-click (or Control-click) Hurakai in Applications, choose Open,
      then click Open in the dialog.

  After that it launches normally. If macOS says the app "is damaged and
  can't be opened", clear the download quarantine flag:

      xattr -dr com.apple.quarantine /Applications/Hurakai.app

  Both are expected for an app distributed outside the App Store without a
  paid Apple Developer ID. Nothing is wrong with the app.

WHAT IT NEEDS
  macOS 14 or later, and a network connection — every forecast, model and
  image is fetched live from NOAA/NWS and NESDIS.

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
