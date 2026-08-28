import AppKit
import SwiftUI

@main
struct FrischMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var panel: FloatingPanel!
    let model = RecentFilesModel()
    var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "clock.arrow.circlepath",
                                           accessibilityDescription: "Frisch")
        let menu = NSMenu()
        let showItem = NSMenuItem(title: "Letzte Dateien anzeigen",
                                  action: #selector(togglePanel), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        let prefItem = NSMenuItem(title: "Einstellungen …",
                                  action: #selector(openSettings), keyEquivalent: ",")
        prefItem.target = self
        menu.addItem(prefItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Frisch beenden",
                                  action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        statusItem.menu = menu

        panel = FloatingPanel(model: model)
        HotKeyManager.shared.callback = { [weak self] in self?.togglePanel() }
        PrefsModel.shared.applyHotKey()

        requestFolderAccessIfNeeded()
        model.refresh() // Spotlight-Query schon beim Start warmlaufen lassen

        if CommandLine.arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.togglePanel()
            }
        }
    }

    @objc func togglePanel() {
        panel.toggle()
    }

    // Löst die einmalige macOS-Freigabe für Schreibtisch/Dokumente/Downloads aus.
    // Ohne die Freigabe filtert TCC diese Ordner stumm aus den Spotlight-Resultaten.
    private func requestFolderAccessIfNeeded() {
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            for folder in ["Desktop", "Documents", "Downloads"] {
                do {
                    let entries = try fm.contentsOfDirectory(atPath: NSHomeDirectory() + "/" + folder)
                    FrischLog.write("Ordnerzugriff \(folder): OK (\(entries.count) Einträge)")
                } catch {
                    FrischLog.write("Ordnerzugriff \(folder): VERWEIGERT (\(error.localizedDescription))")
                }
            }
        }
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 640),
                             styleMask: [.titled, .closable],
                             backing: .buffered, defer: false)
            w.title = "Frisch – Einstellungen"
            w.contentView = NSHostingView(rootView: SettingsView())
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
