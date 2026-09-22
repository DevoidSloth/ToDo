#!/bin/bash
# Builds "Todo List.app" from source. No Xcode project, no dependencies —
# just the Swift compiler from the Command Line Tools.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Todo List"
EXECUTABLE="TodoList"
BUNDLE_ID="com.rubenhayrapetyan.todolist"
VERSION="1.0"

BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP/Contents/MacOS"
RES_DIR="$APP/Contents/Resources"

echo "==> Cleaning"
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"

echo "==> Compiling Swift sources"
xcrun swiftc \
  -O \
  -swift-version 5 \
  -target "$(uname -m)-apple-macos13.0" \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  Sources/*.swift \
  -o "$MACOS_DIR/$EXECUTABLE"

echo "==> Rendering app icon"
ICONSET="$BUILD_DIR/AppIcon.iconset"
xcrun swift tools/MakeIcon.swift "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$RES_DIR/AppIcon.icns"
rm -rf "$ICONSET"

echo "==> Writing Info.plist"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>       <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>        <string>$EXECUTABLE</string>
    <key>CFBundleIdentifier</key>        <string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key>           <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>    <string>13.0</string>
    <key>LSApplicationCategoryType</key> <string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key>   <true/>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP"

# Make Finder pick up the fresh icon and bundle metadata.
touch "$APP"

echo "==> Built $APP"
