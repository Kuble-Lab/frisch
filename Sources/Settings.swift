import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var prefs = PrefsModel.shared

    var body: some View {
        Form {
            Section("Tastaturkürzel") {
                ShortcutRecorderView()
            }
            Section("Start") {
                Toggle("Frisch beim Anmelden starten",
                       isOn: Binding(get: { prefs.launchAtLogin },
                                     set: { prefs.setLaunchAtLogin($0) }))
            }
            Section("Angezeigte Dateitypen") {
                ForEach(FileCategory.allCases, id: \.self) { category in
                    Toggle(category.label, isOn: Binding(
                        get: { prefs.enabledCategories.contains(category.rawValue) },
                        set: { prefs.setCategory(category, enabled: $0) }))
                }
            }
            Section("Ausgeschlossene Ordner") {
                if prefs.excluded.isEmpty {
                    Text("Keine Ordner ausgeschlossen.")
                        .foregroundStyle(.secondary)
                }
                ForEach(prefs.excluded, id: \.self) { path in
                    HStack {
                        Image(systemName: "folder.badge.minus")
                            .foregroundStyle(.secondary)
                        Text(displayPath(path))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            prefs.removeExcluded(path)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .help("Nicht mehr ausschliessen")
                    }
                }
                Button("Ordner hinzufügen …") {
                    addFolder()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 640)
    }

    private func displayPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func addFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.allowsMultipleSelection = true
        p.prompt = "Ausschliessen"
        p.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        if p.runModal() == .OK {
            for url in p.urls {
                prefs.addExcluded(url.path)
            }
        }
    }
}

struct ShortcutRecorderView: View {
    @ObservedObject var prefs = PrefsModel.shared
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text("Panel ein-/ausblenden")
            Spacer()
            Button(recording ? "Tastenkombination drücken … (⎋ bricht ab)" : prefs.shortcutDescription) {
                recording ? stopRecording() : startRecording()
            }
        }
    }

    private func startRecording() {
        recording = true
        HotKeyManager.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = carbonFlags(from: event.modifierFlags)
            if event.keyCode == 53 && mods == 0 { // Esc
                stopRecording()
                return nil
            }
            guard mods != 0 else { return nil } // mindestens ein Modifier
            prefs.setHotKey(code: UInt32(event.keyCode), mods: mods)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
        prefs.applyHotKey()
    }
}
