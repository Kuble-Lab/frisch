#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -g -Onone -parse-as-library -swift-version 5 \
  Sources/RecentFiles.swift Sources/FolderScanner.swift Sources/Prefs.swift Sources/HotKey.swift Sources/Log.swift \
  Tests/FolderScannerTests.swift \
  -framework AppKit -framework SwiftUI -framework Carbon -framework ServiceManagement \
  -framework UniformTypeIdentifiers -o build/FolderScannerTests
build/FolderScannerTests
