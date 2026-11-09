import Foundation
import UniformTypeIdentifiers

// Steuerung und Cache nur auf dem Main-Thread; Dateizugriffe pro Ordner
// separat. Weder Spotlight noch ein langsamer anderer Ordner blockiert Desktop.
final class FolderScanner {
    typealias Scan = (URL, Int) -> [FileItem]

    private final class Folder {
        let url: URL
        let queue: DispatchQueue
        var monitor: DispatchSourceFileSystemObject?
        var scheduled = false
        var scanning = false
        var dirty = false
        var files: [FileItem] = []

        init(_ url: URL) {
            self.url = url
            queue = DispatchQueue(label: "frisch.scan.\(url.lastPathComponent)", qos: .userInitiated)
        }

        deinit { monitor?.cancel() }
    }

    private let folders: [Folder]
    private let scan: Scan
    private let onChange: ([FileItem]) -> Void
    private var windowDays = 30

    init(directories: [URL] = ["Desktop", "Documents", "Downloads"].map {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent($0, isDirectory: true)
    }, scan: @escaping Scan = FolderScanner.scanDirectory,
         onChange: @escaping ([FileItem]) -> Void) {
        folders = directories.map(Folder.init)
        self.scan = scan
        self.onChange = onChange
    }

    func refresh(windowDays: Int) {
        dispatchPrecondition(condition: .onQueue(.main))
        self.windowDays = windowDays
        for folder in folders {
            startMonitor(folder)
            requestScan(folder)
        }
    }

    private func startMonitor(_ folder: Folder) {
        guard folder.monitor == nil else { return }
        let fd = open(folder.url.path, O_EVTONLY)
        guard fd >= 0 else { return } // Beim nächsten Öffnen erneut versuchen.
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .rename, .delete, .revoke], queue: .main)
        source.setEventHandler { [weak self, weak folder] in
            guard let self, let folder, let source = folder.monitor else { return }
            if !source.data.intersection([.rename, .delete, .revoke]).isEmpty {
                source.cancel()
                folder.monitor = nil
            }
            // Führende Flanke: fortlaufende Events verschieben den Scan nicht
            // endlos. Während eines Scans höchstens einen Nachlauf vormerken.
            guard !folder.scheduled else { return }
            folder.scheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self, weak folder] in
                guard let self, let folder else { return }
                folder.scheduled = false
                self.requestScan(folder)
            }
        }
        source.setCancelHandler { close(fd) }
        folder.monitor = source
        source.resume()
    }

    private func requestScan(_ folder: Folder) {
        guard !folder.scanning else {
            folder.dirty = true
            return
        }
        folder.scanning = true
        folder.dirty = false
        let days = windowDays
        let scan = self.scan
        folder.queue.async { [weak self, weak folder] in
            guard let folder else { return }
            let files = scan(folder.url, days)
            DispatchQueue.main.async { [weak self, weak folder] in
                guard let self, let folder else { return }
                folder.files = files
                folder.scanning = false
                self.onChange(self.folders.flatMap(\.files))
                if folder.dirty { self.requestScan(folder) }
            }
        }
    }

    static func scanDirectory(_ directory: URL, windowDays: Int) -> [FileItem] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .creationDateKey,
                                       .addedToDirectoryDateKey, .contentTypeKey, .isDirectoryKey]
        let since = Date().addingTimeInterval(-Double(windowDays) * 86400)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else {
            return []
        }
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys),
                  let date = [values.contentModificationDate, values.creationDate,
                              values.addedToDirectoryDate].compactMap({ $0 }).max(),
                  date > since else { return nil }
            let category: FileCategory
            if values.isDirectory == true { category = .folders }
            else if let type = values.contentType { category = FileCategory.classify(utType: type) }
            else { category = .other }
            return FileItem(url: url, date: date, category: category)
        }
    }
}
