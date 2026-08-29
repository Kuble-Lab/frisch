#!/bin/zsh
set -e
cd "$(dirname "$0")"
mkdir -p build

swiftc -O -parse-as-library -swift-version 5 \
  Sources/*.swift \
  -framework AppKit -framework SwiftUI -framework Carbon -framework ServiceManagement \
  -framework QuickLookThumbnailing -framework UniformTypeIdentifiers -framework Quartz \
  -target arm64-apple-macos13.0 \
  -o build/Frisch

APP=build/Frisch.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp build/Frisch "$APP/Contents/MacOS/Frisch"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "Build OK: $APP"
