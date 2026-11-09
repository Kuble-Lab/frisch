import Foundation

@main
struct FolderScannerTests {
    static func wait(_ description: String, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(2)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        precondition(condition(), description)
    }

    static func main() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        let desktop = root.appendingPathComponent("Desktop")
        let documents = root.appendingPathComponent("Documents")
        let downloads = root.appendingPathComponent("Downloads")
        for dir in [desktop, documents, downloads] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let blocked = DispatchSemaphore(value: 0)
        defer { blocked.signal() }
        var files: [FileItem] = []
        let scanner = FolderScanner(directories: [desktop, documents, downloads], scan: { url, days in
            if url == documents { blocked.wait() }
            return FolderScanner.scanDirectory(url, windowDays: days)
        }, onChange: { files = $0 })
        let first = desktop.appendingPathComponent("first.png")
        try Data([1]).write(to: first)
        scanner.refresh(windowDays: 30)
        wait("Desktop muss trotz blockiertem Documents-Scan erscheinen") {
            files.contains { $0.url.resolvingSymlinksInPath().path == first.resolvingSymlinksInPath().path && $0.category == .images }
        }
        let screenshot = desktop.appendingPathComponent("screenshot.png")
        let start = Date()
        try Data([2]).write(to: screenshot, options: .atomic)
        wait("Neuer Screenshot muss ohne Refresh erscheinen") {
            files.contains { $0.url.resolvingSymlinksInPath().path == screenshot.resolvingSymlinksInPath().path }
        }
        print(String(format: "Dateisystem-Event bis Ergebnis: %.3f s", Date().timeIntervalSince(start)))
        let download = downloads.appendingPathComponent("download.pdf")
        try Data([4]).write(to: download, options: .atomic)
        wait("Downloads muss ebenfalls unabhängig aktualisieren") {
            files.contains { $0.url.resolvingSymlinksInPath().path == download.resolvingSymlinksInPath().path && $0.category == .documents }
        }
        try FileManager.default.removeItem(at: first)
        wait("Gelöschte Dateien müssen aus dem Scan verschwinden") {
            !files.contains { $0.url.resolvingSymlinksInPath().path == first.resolvingSymlinksInPath().path }
        }
        let hidden = desktop.appendingPathComponent(".hidden.png")
        try Data([3]).write(to: hidden)
        let direct = FolderScanner.scanDirectory(desktop, windowDays: 30)
        precondition(!direct.contains { $0.url.resolvingSymlinksInPath().path == hidden.resolvingSymlinksInPath().path })
        precondition(direct.contains { $0.url.resolvingSymlinksInPath().path == screenshot.resolvingSymlinksInPath().path })
        withExtendedLifetime(scanner) {}
        print("PASS: unabhängige Ordner, initialer Scan, Live-Events, Löschung, versteckte Dateien")
    }
}
