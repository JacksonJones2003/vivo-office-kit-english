#!/bin/bash
# Build the native iCloud Photos window used by the vivo Office Kit patch.
#   ./build.sh                       # install to the standard location
#   ./build.sh /tmp/iCloud\ Photos.app
# Requires the Xcode Command Line Tools (swiftc). No Apple developer account is needed.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="${1:-$HOME/Library/Application Support/vivo-office-kit-icloud-photos/iCloud Photos.app}"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "swiftc was not found. Install the Xcode Command Line Tools first:" >&2
  echo "  xcode-select --install" >&2
  exit 1
fi

rm -rf "$DEST"
mkdir -p "$DEST/Contents/MacOS" "$DEST/Contents/Resources"

cat > "$DEST/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>iCloudPhotos</string>
  <key>CFBundleIdentifier</key><string>com.jacksonjones.vivo-icloud-photos</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>iCloud Photos</string>
  <key>CFBundleDisplayName</key><string>iCloud Photos</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.photography</string>
  <key>NSHumanReadableCopyright</key><string>Uses iCloud.com/Photos through Apple WebKit. Not affiliated with Apple or vivo.</string>
</dict>
</plist>
PLIST

swiftc -O -swift-version 5 "$HERE/iCloudPhotos.swift" \
  -o "$DEST/Contents/MacOS/iCloudPhotos" \
  -framework Cocoa -framework WebKit

chmod +x "$DEST/Contents/MacOS/iCloudPhotos"
codesign --force --deep --sign - "$DEST" >/dev/null 2>&1 || true
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
echo "Built $DEST"
