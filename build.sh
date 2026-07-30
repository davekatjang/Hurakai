#!/bin/bash
# Builds Hurakai.app.
#
# ponytail: swiftc directly, no SwiftPM manifest. WebKit and MapKit need a real bundle
# (bundle id + Info.plist) either way, so the manifest bought nothing — and the
# PackageDescription lib shipped with Command Line Tools fails to link at any
# tools-version. One compile, one bundle, done.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Hurakai.app"
SDK="$(xcrun --show-sdk-path)"
ARCH="$(uname -m)"
DEPLOY="14.0"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O \
    -target "${ARCH}-apple-macosx${DEPLOY}" \
    -sdk "$SDK" \
    -o "$APP/Contents/MacOS/Hurakai" \
    Sources/Hurakai/*.swift

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Hurakai</string>
    <key>CFBundleDisplayName</key><string>Hurakai</string>
    <key>CFBundleExecutable</key><string>Hurakai</string>
    <key>CFBundleIdentifier</key><string>io.hurakai.tracker</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHumanReadableCopyright</key>
    <string>Data courtesy NOAA/NWS National Hurricane Center, Central Pacific Hurricane Center and NESDIS.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "note: ad-hoc signing skipped"
echo "Built $APP"
