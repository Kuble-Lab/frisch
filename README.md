# Frisch 🍃

A tiny native macOS menu bar app that shows your recently used files in a floating panel — summoned with a global keyboard shortcut. Built as a replacement for the discontinued Fresh.app.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5-orange) ![License: MIT](https://img.shields.io/badge/License-MIT-green)

## Features

- **Global shortcut** (default ⌥⌘F, fully configurable) opens a floating panel with your latest files
- **Instant**: a persistent Spotlight query with live updates — no per-open scanning
- **Hybrid source**: Spotlight (`kMDItemLastUsedDate` / `kMDItemDateAdded` / `kMDItemFSCreationDate`) plus a direct scan of the TCC-protected folders Desktop/Documents/Downloads (Spotlight queries return nothing for those, even with file access granted — new screenshots still show up instantly)
- **Finder-like list** (NSTableView): click selects, ⇧/⌘ multi-select, **Space = Quick Look**, **Return opens**, **double-click reveals in Finder**, **drag & drop** carries all selected files
- **QuickLook thumbnails** for images, videos and PDFs
- **File-type filters** (images / videos / audio / documents / code / folders / other)
- "Load older …" progressively widens the time window (30 days → ~10 years)
- Settings: shortcut recorder, launch at login, excluded folders
- Panel hides automatically when you switch to another app
- Diagnostics log: `~/Library/Logs/frisch.log`

## Install

**Download**: grab the latest `Frisch-x.y.dmg` from [Releases](https://github.com/Kuble-Lab/frisch/releases), open it and drag **Frisch.app** to **Applications**.

The app is not notarized (no Apple Developer subscription). On first launch macOS will warn about an unidentified developer:

- **macOS 14 and earlier**: right-click Frisch.app → **Open** → **Open**.
- **macOS 15+**: try to open it once, then go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**.

Then allow access to Desktop/Documents/Downloads when asked — that's what the app lists.

## Build from source

No Xcode project — plain `swiftc`:

```sh
./build.sh              # builds build/Frisch.app (arm64, ad-hoc signed)
UNIVERSAL=1 ./build.sh  # universal binary (Apple Silicon + Intel)
cp -R build/Frisch.app /Applications/
```

Requires Xcode or a Swift toolchain (Swift 5.9+, SwiftUI, macOS 13+).

Regenerate the app icon: `swift Scripts/makeicon.swift && iconutil -c icns AppIcon.iconset -o AppIcon.icns`

## Architecture

| File | Purpose |
|---|---|
| `Sources/Main.swift` | App delegate, status menu, settings window, TCC trigger |
| `Sources/Panel.swift` | Floating panel (NSPanel) + NSTableView list with SwiftUI rows |
| `Sources/RecentFiles.swift` | Data model: Spotlight query, folder scan, classification, filters |
| `Sources/HotKey.swift` | Global hotkey (Carbon `RegisterEventHotKey`) |
| `Sources/Prefs.swift` | UserDefaults, login item (SMAppService), filter prefs |
| `Sources/Settings.swift` | Settings UI incl. shortcut recorder |
| `Sources/Thumbnails.swift` | QuickLook thumbnails with cache |
| `Sources/Log.swift` | Diagnostics log |

## Hard-earned macOS lessons

- `NSMetadataQuery` with a custom `operationQueue`: **`start()` must run on that queue**, otherwise the query never delivers.
- Spotlight queries return **no results** for TCC-protected folders (Desktop/Documents/Downloads), even when `FileManager` access is granted → scan them yourself and merge.
- `isMovableByWindowBackground = true` eats file drags from lists — the drag attempt moves the window instead.
- Synthetic events (IOHID/SkyLight) trigger neither Carbon hotkeys nor real drag sessions — test those features with real input only.
- Ad-hoc signing → macOS may re-ask for TCC folder permissions after every rebuild.

## License

[MIT](LICENSE)
