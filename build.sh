#!/bin/zsh
set -e
cd "$(dirname "$0")"
mkdir -p build

FRAMEWORKS=(-framework AppKit -framework SwiftUI -framework Carbon -framework ServiceManagement
            -framework QuickLookThumbnailing -framework UniformTypeIdentifiers -framework Quartz)

if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  # Universal Binary (Apple Silicon + Intel) — für Releases.
  swiftc -O -parse-as-library -swift-version 5 Sources/*.swift \
    "${FRAMEWORKS[@]}" -target arm64-apple-macos13.0 -o build/Frisch-arm64
  swiftc -O -parse-as-library -swift-version 5 Sources/*.swift \
    "${FRAMEWORKS[@]}" -target x86_64-apple-macos13.0 -o build/Frisch-x86_64
  lipo -create build/Frisch-arm64 build/Frisch-x86_64 -output build/Frisch
else
  swiftc -O -parse-as-library -swift-version 5 Sources/*.swift \
    "${FRAMEWORKS[@]}" -target arm64-apple-macos13.0 -o build/Frisch
fi

APP=build/Frisch.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp build/Frisch "$APP/Contents/MacOS/Frisch"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "Build OK: $APP"
