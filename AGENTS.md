# Frisch

Kleine native macOS-Menüleisten-App, die die zuletzt verwendeten Dateien in einem schwebenden Panel zeigt (globaler Shortcut, Standard ⌥⌘F). Ersatz für die eingestellte App Fresh.app.

## Stack
- Swift 5.9+, SwiftUI/AppKit, kein Xcode-Projekt (reines `swiftc`)
- macOS 13+, Spotlight-Abfrage (NSMetadataQuery) plus direkte Ordner-Scans

## Wichtige Ordner und Dateien
- `Sources/` Swift-Quellcode, `Scripts/makeicon.swift` Icon-Erzeugung, `build.sh` Build-Skript
- `Info.plist`, `AppIcon.icns`, `.github/workflows/release.yml` Release-Workflow
- Diagnose-Log: `~/Library/Logs/frisch.log`

## Befehle
```sh
./build.sh              # baut build/Frisch.app (arm64, ad-hoc signiert)
UNIVERSAL=1 ./build.sh  # Universal-Binary
```
Installieren: Download des DMG aus den GitHub-Releases. Tests: Unbekannt.

## Deploy und Betrieb
- Nicht notarisiert; Verteilung als DMG über GitHub Releases.

## Repo
- https://github.com/Kuble-Lab/frisch

## Regeln
- Texte an Gustavo auf Schweizer Hochdeutsch (kein ß).
- Keine Zugangsdaten, Tokens oder `.env`-Inhalte in Dateien, Commits oder Berichte schreiben.
- Änderungen immer per Branch + Pull Request, nie direkt auf `main`.
- Nach jeder Arbeit das GTS-Projektregister nachführen: Brain `kuble.projekt.gu-agent-projekte` (Registerzeile) und die passende Detaildatei (ID: Unbekannt, im Brain nachschlagen).
