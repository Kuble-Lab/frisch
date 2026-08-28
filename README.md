# Frisch 🍃

Native macOS-Menüleisten-App, die die zuletzt benutzten Dateien anzeigt — Eigenbau-Ersatz für die eingestellte Fresh.app (Ironic Software).

## Features

- **Globaler Shortcut** (Standard ⌥⌘F, frei belegbar) öffnet ein Floating-Panel mit den letzten Dateien
- **Sofort offen:** persistente Spotlight-Query mit Live-Updates statt Abfrage pro Öffnen
- **Hybrid-Quelle:** Spotlight (`kMDItemLastUsedDate` / `kMDItemDateAdded` / `kMDItemFSCreationDate`) plus direkter Scan der TCC-geschützten Ordner Schreibtisch/Dokumente/Downloads — Spotlight liefert für diese Ordner keine Query-Resultate, selbst mit erteilter Dateifreigabe
- **QuickLook-Vorschauen** für Bilder, Videos und PDFs
- **Dateityp-Filter** (Bilder / Videos / Audio / Dokumente / Code / Ordner / Andere)
- Klick öffnet, Buttons für **Im Finder zeigen** und **Teilen**, **Drag & Drop** aus der Liste
- «Ältere laden …» erweitert das Zeitfenster schrittweise (30 Tage → ~10 Jahre)
- Einstellungen: Shortcut-Recorder, Autostart (Login Item), ausgeschlossene Ordner
- Diagnose-Log: `~/Library/Logs/frisch.log`

## Build

Kein Xcode-Projekt — direkte `swiftc`-Kompilierung:

```sh
./build.sh          # baut build/Frisch.app (arm64, ad-hoc signiert)
cp -R build/Frisch.app /Applications/
```

Benötigt Xcode bzw. eine Swift-Toolchain (Swift 5.9+, SwiftUI, macOS 13+).

App-Icon neu generieren: `swift Scripts/makeicon.swift && iconutil -c icns AppIcon.iconset -o AppIcon.icns`

## Architektur

| Datei | Zweck |
|---|---|
| `Sources/Main.swift` | App-Delegate, Statusmenü, Settings-Fenster, TCC-Trigger |
| `Sources/Panel.swift` | Floating-Panel (NSPanel) + SwiftUI-Liste mit Zeilen |
| `Sources/RecentFiles.swift` | Datenmodell: Spotlight-Query, Ordner-Scan, Kategorisierung, Filter |
| `Sources/HotKey.swift` | Globaler Hotkey (Carbon `RegisterEventHotKey`) |
| `Sources/Prefs.swift` | UserDefaults, Login-Item (SMAppService), Filter-Prefs |
| `Sources/Settings.swift` | Einstellungen inkl. Shortcut-Recorder |
| `Sources/Thumbnails.swift` | QuickLook-Thumbnails mit Cache |
| `Sources/Log.swift` | Diagnose-Log |

## Gelernte Fallen (hart erarbeitet)

- `NSMetadataQuery` mit eigener `operationQueue`: **`start()` muss auf dieser Queue laufen**, sonst liefert die Query nie.
- Spotlight-Queries geben für TCC-geschützte Ordner (Desktop/Documents/Downloads) **keine Resultate** zurück, auch wenn `FileManager`-Zugriff gewährt ist → eigener Scan nötig.
- `isMovableByWindowBackground = true` frisst Datei-Drags aus Listen — der Zieh-Versuch verschiebt das Fenster.
- Synthetische Events (IOHID/SkyLight) triggern weder Carbon-Hotkeys noch echte Drag-Sessions — solche Features nur mit echten Eingaben testen.
- Ad-hoc-Signatur → TCC-Freigaben können nach jedem Rebuild erneut abgefragt werden.
