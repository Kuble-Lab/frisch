# Frisch 🍃

A tiny native macOS menu bar app that shows your recently used files in a floating panel — summoned with a global keyboard shortcut. Built as a replacement for the discontinued Fresh.app.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5-orange) ![License: MIT](https://img.shields.io/badge/License-MIT-green)

## Features

- **Global shortcut** (default ⌥⌘F, fully configurable) opens a floating panel with your latest files
- **Instant**: a persistent Spotlight query with live updates — no per-open scanning
- **Hybrid source**: Spotlight (`kMDItemLastUsedDate` / `kMDItemDateAdded` / `kMDItemFSCreationDate`) plus a direct scan of the TCC-protected folders Desktop/Documents/Downloads (Spotlight queries return nothing for those, even with file access granted)
- **Live folder watching**: Desktop/Documents/Downloads are monitored with dispatch sources — a new screenshot or download appears in the list instantly, even while the panel is open
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

## How to use

**Open the panel**: press **⌥⌘F** (or click the menu bar icon → "Letzte Dateien anzeigen"). The shortcut is configurable in Settings. Press **Esc** to close — or just click into another app, the panel hides itself.

The list works like the Finder:

| Action | Result |
|---|---|
| Click | Select a file |
| ⇧-click / ⌘-click | Select a range / toggle individual files |
| **Space** | Quick Look the selection (arrow keys browse, Space closes) |
| **Return** | Open the selected file(s) |
| **Double-click** | Reveal the file in its folder in Finder |
| **Drag** | Drag & drop all selected files anywhere (Finder, Mail, Slack, browser …) |
| Right-click | Context menu: Open, Reveal in Finder, Quick Look |
| ↑ / ↓ | Move through the list |

Each row also has two buttons: **reveal in Finder** (folder icon) and **share** (share icon).

At the bottom, **"Ältere laden …"** loads older files by progressively widening the time window.

**Settings** (gear icon, or menu bar icon → "Einstellungen …"):

- **Shortcut**: click the recorder field and press your new key combination (Esc cancels)
- **Autostart**: launch Frisch at login
- **File types**: show only the categories you care about (images, videos, audio, documents, code, folders, other)
- **Excluded folders**: hide files from specific folders

On first launch, allow access to Desktop, Documents and Downloads when macOS asks — these folders are scanned directly so new screenshots and downloads appear instantly.

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
- Spotlight queries return **no results** for TCC-protected folders (Desktop/Documents/Downloads), even when `FileManager` access is granted → scan them yourself and merge. And since Spotlight never fires updates for them either, watch those folders with dispatch sources or new files won't appear while the UI is open.
- A home-scope `NSMetadataQuery` for "recent files" returned **74k results** — 96% from Dropbox sync and `~/Library` caches that were filtered out client-side anyway. Building `NSMetadataItem`s for all of them took ~110 s per update and starved the serial queue. Scope the query to the folders you actually show (home minus Library minus exclusions): 74k → 2.9k results, 110 s → 3 s.
- `NSMetadataQuery.value(ofAttribute:forResultAt:)` silently returns nil unless the attribute is registered via `sortDescriptors`/`valueListAttributes` — and server-side `sortDescriptors` made gathering never finish on large result sets. Use `result(at:)` on a small, well-scoped result set instead.
- `isMovableByWindowBackground = true` eats file drags from lists — the drag attempt moves the window instead.
- Synthetic events (IOHID/SkyLight) trigger neither Carbon hotkeys nor real drag sessions — test those features with real input only.
- Ad-hoc signing → macOS may re-ask for TCC folder permissions after every rebuild.

## License

[MIT](LICENSE)
