import AppKit
import Carbon
import ServiceManagement

final class PrefsModel: ObservableObject {
    static let shared = PrefsModel()
    private let d = UserDefaults.standard

    @Published var keyCode: UInt32
    @Published var modifiers: UInt32 // Carbon-Flags
    @Published var excluded: [String]
    @Published var launchAtLogin: Bool
    @Published var enabledCategories: Set<String>

    private init() {
        d.register(defaults: [
            "hotKeyCode": 3,                                  // F
            "hotKeyModifiers": Int(UInt32(cmdKey) | UInt32(optionKey)), // ⌥⌘
        ])
        keyCode = UInt32(d.integer(forKey: "hotKeyCode"))
        modifiers = UInt32(d.integer(forKey: "hotKeyModifiers"))
        excluded = d.stringArray(forKey: "excludedFolders") ?? [NSHomeDirectory() + "/Library"]
        launchAtLogin = SMAppService.mainApp.status == .enabled
        enabledCategories = Set(d.stringArray(forKey: "enabledCategories")
            ?? FileCategory.allCases.map(\.rawValue))
    }

    func setCategory(_ category: FileCategory, enabled: Bool) {
        if enabled {
            enabledCategories.insert(category.rawValue)
        } else {
            enabledCategories.remove(category.rawValue)
        }
        d.set(Array(enabledCategories), forKey: "enabledCategories")
        NotificationCenter.default.post(name: .frischFilterChanged, object: nil)
    }

    var shortcutDescription: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + keyName(keyCode)
    }

    func setHotKey(code: UInt32, mods: UInt32) {
        keyCode = code
        modifiers = mods
        d.set(Int(code), forKey: "hotKeyCode")
        d.set(Int(mods), forKey: "hotKeyModifiers")
        applyHotKey()
    }

    func applyHotKey() {
        HotKeyManager.shared.register(keyCode: keyCode, modifiers: modifiers)
    }

    func addExcluded(_ path: String) {
        guard !excluded.contains(path) else { return }
        excluded.append(path)
        saveExcluded()
    }

    func removeExcluded(_ path: String) {
        excluded.removeAll { $0 == path }
        saveExcluded()
    }

    private func saveExcluded() {
        d.set(excluded, forKey: "excludedFolders")
        NotificationCenter.default.post(name: .frischFilterChanged, object: nil)
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Frisch: Login-Item-Fehler: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
