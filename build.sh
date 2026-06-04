#!/bin/bash
# Builds ClaudeLimitsMenuBar and packages it into a double-clickable .app bundle.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Claude Limits"
BUNDLE_ID="com.local.claudelimits"
EXECUTABLE="ClaudeLimitsMenuBar"
APP_DIR="build/${APP_NAME}.app"

echo "==> swift build -c release"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/${EXECUTABLE}"
if [[ ! -f "$BIN_PATH" ]]; then
  echo "Build product not found at $BIN_PATH" >&2
  exit 1
fi

echo "==> assembling ${APP_DIR}"
rm -rf "$APP_DIR"
mkdir -p "${APP_DIR}/Contents/MacOS"
cp "$BIN_PATH" "${APP_DIR}/Contents/MacOS/${EXECUTABLE}"

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc codesign so the Keychain entry's ACL recognizes a stable identity and
# Launch-at-Login / Keychain access work without re-prompting on every rebuild.
echo "==> ad-hoc codesign"
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || \
  echo "(codesign skipped — app still runs)"

echo "==> done: $APP_DIR"
echo "Run it with:  open \"$APP_DIR\""
