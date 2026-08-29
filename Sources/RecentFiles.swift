import AppKit
import Foundation
import UniformTypeIdentifiers

extension Notification.Name {
    static let frischFilterChanged = Notification.Name("frischFilterChanged")
}

enum FileCategory: String, CaseIterable {
    case images, videos, audio, documents, code, folders, other

    var label: String {
        switch self {
        case .images: return "Bilder"
        case .videos: return "Videos"
        case .audio: return "Audio"
        case .documents: return "Dokumente"
        case .code: return "Code"
        case .folders: return "Ordner"
        case .other: return "Andere"
        }
    }

    static func classify(typeTree: [String]) -> FileCategory {
        if typeTree.contains("public.folder") { return .folders }
        if typeTree.contains("public.image") { return .images }
        if typeTree.contains("public.movie") || typeTree.contains("public.video") { return .videos }
        if typeTree.contains("public.audio") { return .audio }
        // Code VOR Dokumente prüfen: Quelltexte konformieren zu public.text
        // und würden sonst als Dokument durchrutschen.
        let codeMarkers = ["source-code", "public.script", "shell-script", "json", "yaml",
                           "property-list", "c-header", "makefile", "xml", "swift-source"]
        if typeTree.contains(where: { t in codeMarkers.contains(where: { t.contains($0) }) }) {
            return .code
        }
        let docMarkers = ["pdf", "text", "word", "spreadsheet", "presentation",
                          "composite-content", "rtf", "ebook", "keynote", "pages", "numbers"]
        if typeTree.contains(where: { t in docMarkers.contains(where: { t.contains($0) }) }) {
            return .documents
        }
        return .other
    }

    static func classify(utType t: UTType) -> FileCategory {
        if t.conforms(to: .folder) { return .folders }
        if t.conforms(to: .image) { return .images }
        if t.conforms(to: .movie) || t.conforms(to: .video) { return .videos }
        if t.conforms(to: .audio) { return .audio }
        if t.conforms(to: .sourceCode) || t.conforms(to: .script) || t.conforms(to: .shellScript)
            || t.conforms(to: .json) || t.conforms(to: .yaml) || t.conforms(to: .xml)
            || t.conforms(to: .propertyList) {
            return .code
        }
        if t.conforms(to: .pdf) || t.conforms(to: .text) || t.conforms(to: .presentation)
            || t.conforms(to: .spreadsheet) || t.conforms(to: .compositeContent) {
            return .documents
        }
        return .other
    }
}

struct FileItem: Identifiable {
    let url: URL
    let date: Date
    let category: FileCategory
    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

final class RecentFilesModel: NSObject, ObservableObject {
    @Published var items: [FileItem] = []
    @Published var isLoading = false

    private var query: NSMetadataQuery?
    private var all: [FileItem] = []
    private var spotlightCache: [FileItem] = []
    private var manualCache: [FileItem] = []
    private var manualCacheTime = Date.distantPast
    private var folderMonitors: [DispatchSourceFileSystemObject] = []
    private var monitorDebounce: DispatchWorkItem?
    private var shown = 50
    private let page = 50
    private var windowDays = 30
    private let maxWindowDays = 3660

    // Serielle Hintergrund-Queue: Query-Notifications und Verarbeitung laufen hier,
    // damit der Main-Thread (UI, Hotkey) nie blockiert.
    private let queryQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInitiated
        q.name = "frisch.query"
        return q
    }()

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(filterChanged),
                                               name: .frischFilterChanged, object: nil)
    }

    @objc private func filterChanged() {
        queryQueue.addOperation { self.publish() }
    }

    private var filteredAll: [FileItem] {
        let prefs = PrefsModel.shared
        let enabled = prefs.enabledCategories
        let excluded = prefs.excluded
        return all.filter { item in
            guard enabled.contains(item.category.rawValue) else { return false }
            let path = item.url.path
            return !excluded.contains(where: { path == $0 || path.hasPrefix($0 + "/") })
        }
    }

    var canLoadMore: Bool {
        shown < filteredAll.count || windowDays < maxWindowDays
    }

    // Die Query läuft dauerhaft (Live-Updates); das Panel-Öffnen publiziert nur noch.
    func refresh() {
        if query == nil {
            run()
        } else {
            // Geschützte Ordner frisch scannen (neue Screenshots!), dann publizieren.
            enqueueRemerge()
        }
    }

    // Remerge-Ops überholen wartende process()-Läufe (gleiche serielle Queue).
    private func enqueueRemerge() {
        let op = BlockOperation { [weak self] in self?.remergeManualFolders() }
        op.queuePriority = .veryHigh
        queryQueue.addOperation(op)
    }

    func loadMore() {
        shown += page
        queryQueue.addOperation {
            if self.shown > self.filteredAll.count && self.windowDays < self.maxWindowDays {
                DispatchQueue.main.async {
                    self.windowDays = min(self.windowDays * 4, self.maxWindowDays)
                    self.run()
                }
            } else {
                self.publish()
            }
        }
    }

    // Spotlight liefert für Desktop/Dokumente/Downloads keine Live-Updates
    // (siehe process()) — ohne eigene Überwachung erscheint ein neuer Screenshot
    // bei offenem Panel erst, wenn zufällig ein anderes Spotlight-Event feuert.
    // Darum: die drei Ordner direkt beobachten und sofort neu publizieren.
    private func startFolderMonitors() {
        guard folderMonitors.isEmpty else { return }
        for folder in ["Desktop", "Documents", "Downloads"] {
            let fd = open(NSHomeDirectory() + "/" + folder, O_EVTONLY)
            guard fd >= 0 else { continue }
            let src = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: [.write, .extend, .rename],
                queue: .global(qos: .utility))
            src.setEventHandler { [weak self] in self?.folderChanged() }
            src.setCancelHandler { close(fd) }
            src.resume()
            folderMonitors.append(src)
        }
        FrischLog.write("Ordner-Monitore aktiv: \(folderMonitors.count)")
    }

    private func folderChanged() {
        // Kurz entprellen: ein Screenshot löst mehrere Verzeichnis-Events aus.
        monitorDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            FrischLog.write("Ordner-Änderung erkannt — Neuscan Desktop/Dokumente/Downloads")
            self.enqueueRemerge()
        }
        monitorDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    // Home-Ordner MINUS Library MINUS ausgeschlossene Ordner als Scopes.
    // Grund (gemessen): ~96 % der Home-Scope-Resultate stammten aus
    // «Agency Dropbox» und «Library» — beide wurden erst NACH der teuren
    // Verarbeitung weggefiltert; process() über ~74k Items dauerte 110 s
    // und blockierte die Queue minutenlang (Screenshots erschienen nicht).
    private func buildSearchScopes() -> [Any] {
        let fm = FileManager.default
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let excluded = PrefsModel.shared.excluded
        guard let entries = try? fm.contentsOfDirectory(at: home,
                                                        includingPropertiesForKeys: [.isDirectoryKey],
                                                        options: [.skipsHiddenFiles]) else {
            return [NSMetadataQueryUserHomeScope]
        }
        var scopes: [URL] = []
        for url in entries {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            if url.lastPathComponent == "Library" { continue }
            let path = url.path
            if excluded.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { continue }
            scopes.append(url)
        }
        FrischLog.write("Such-Scopes: \(scopes.count) Ordner (Home minus Library/Ausschlüsse)")
        return scopes.isEmpty ? [NSMetadataQueryUserHomeScope] : scopes
    }

    private func run() {
        isLoading = true
        startFolderMonitors()
        stopQuery()
        let q = NSMetadataQuery()
        let since = Date().addingTimeInterval(-Double(windowDays) * 86400) as NSDate
        // Kurzes Fenster für "neu erstellt/hinzugefügt": hält das Resultat klein
        // (sonst fluten Build-Artefakte und Caches der letzten 30 Tage die Query).
        let sinceNew = Date().addingTimeInterval(-Double(min(windowDays, 7)) * 86400) as NSDate
        q.predicate = NSPredicate(format: "%K > %@ OR kMDItemDateAdded > %@ OR %K > %@",
                                  NSMetadataItemLastUsedDateKey, since,
                                  sinceNew,
                                  NSMetadataItemFSCreationDateKey, sinceNew)
        // KEINE sortDescriptors: serverseitiges Sortieren liess das Gathering
        // nie fertig werden (>8 min statt ~70 s bei ~74k Resultaten).
        q.searchScopes = buildSearchScopes()
        q.notificationBatchingInterval = 5.0
        q.operationQueue = queryQueue
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(gatherProgress(_:)),
                       name: .NSMetadataQueryGatheringProgress, object: q)
        nc.addObserver(self, selector: #selector(gatherDone(_:)),
                       name: .NSMetadataQueryDidFinishGathering, object: q)
        nc.addObserver(self, selector: #selector(queryUpdated(_:)),
                       name: .NSMetadataQueryDidUpdate, object: q)
        query = q
        // start() muss auf der operationQueue der Query laufen, sonst liefert sie nie.
        queryQueue.addOperation { q.start() }
    }

    private func stopQuery() {
        guard let q = query else { return }
        query = nil
        let nc = NotificationCenter.default
        nc.removeObserver(self, name: .NSMetadataQueryGatheringProgress, object: q)
        nc.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: q)
        nc.removeObserver(self, name: .NSMetadataQueryDidUpdate, object: q)
        queryQueue.addOperation { q.stop() }
    }

    @objc private func gatherProgress(_ note: Notification) {
        // Während des ersten Gatherings nur ein schnelles Teilbild publizieren,
        // damit das Panel sofort etwas zeigt — Vollverarbeitung erst am Ende.
        if all.count < 200 {
            process(limit: 800)
        }
    }

    @objc private func queryUpdated(_ note: Notification) {
        process()
    }

    @objc private func gatherDone(_ note: Notification) {
        process()
        FrischLog.write("Gathering fertig: \(query?.resultCount ?? -1) Spotlight-Resultate, \(all.count) Einträge nach Dedupe")
        let desktopCount = all.filter { $0.url.path.hasPrefix(NSHomeDirectory() + "/Desktop/") }.count
        FrischLog.write("Davon auf dem Schreibtisch: \(desktopCount)")
        DispatchQueue.main.async { self.isLoading = false }
    }

    private func process(limit: Int = .max) {
        guard let q = query else { return }
        q.disableUpdates()
        defer { q.enableUpdates() }

        var seen = Set<String>()
        var out: [FileItem] = []
        // ACHTUNG: value(ofAttribute:forResultAt:) liefert nur für Attribute
        // aus sortDescriptors/valueListAttributes etwas — sonst still nil.
        // Also result(at:) mit NSMetadataItem; billig genug, weil die Scopes
        // die Junk-Ordner (Dropbox/Library, 96 % der Resultate) ausklammern.
        let count = min(q.resultCount, limit)
        out.reserveCapacity(min(count, 5000))

        for i in 0..<count {
            guard let item = q.result(at: i) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String
            else { continue }
            if seen.contains(path) { continue }
            let dates = [
                item.value(forAttribute: NSMetadataItemLastUsedDateKey) as? Date,
                item.value(forAttribute: "kMDItemDateAdded") as? Date,
                item.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date,
            ].compactMap { $0 }
            guard let date = dates.max() else { continue }
            let tree = item.value(forAttribute: "kMDItemContentTypeTree") as? [String] ?? []
            seen.insert(path)
            out.append(FileItem(url: URL(fileURLWithPath: path), date: date,
                                category: FileCategory.classify(typeTree: tree)))
        }
        spotlightCache = out
        // Spotlight liefert für TCC-geschützte Ordner (Desktop/Dokumente/Downloads)
        // KEINE Resultate, obwohl Dateizugriff erlaubt ist — die scannen wir selbst.
        if Date().timeIntervalSince(manualCacheTime) > 10 {
            manualCache = scanProtectedFolders()
            manualCacheTime = Date()
        }
        mergeAndPublish()
    }

    // Schneller Pfad für Ordner-Events und Panel-Öffnen: nur die drei Ordner
    // neu scannen und mit dem letzten Spotlight-Stand mergen. process() über
    // 70k+ Spotlight-Items dauert Sekunden — ein neuer Screenshot soll aber
    // sofort erscheinen.
    private func remergeManualFolders() {
        manualCache = scanProtectedFolders()
        manualCacheTime = Date()
        mergeAndPublish()
    }

    private func mergeAndPublish() {
        var seen = Set<String>()
        var out: [FileItem] = []
        out.reserveCapacity(spotlightCache.count + manualCache.count)
        for itm in spotlightCache where seen.insert(itm.url.path).inserted { out.append(itm) }
        for itm in manualCache where !seen.contains(itm.url.path) {
            seen.insert(itm.url.path)
            out.append(itm)
        }
        out.sort { $0.date > $1.date }
        all = out
        publish()
    }

    private func scanProtectedFolders() -> [FileItem] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .creationDateKey,
                                      .addedToDirectoryDateKey, .contentTypeKey, .isDirectoryKey]
        let since = Date().addingTimeInterval(-Double(windowDays) * 86400)
        var out: [FileItem] = []
        for folder in ["Desktop", "Documents", "Downloads"] {
            let dir = URL(fileURLWithPath: NSHomeDirectory() + "/" + folder, isDirectory: true)
            guard let urls = try? fm.contentsOfDirectory(at: dir,
                                                         includingPropertiesForKeys: keys,
                                                         options: [.skipsHiddenFiles]) else { continue }
            for url in urls {
                guard let vals = try? url.resourceValues(forKeys: Set(keys)) else { continue }
                let dates = [vals.contentModificationDate, vals.creationDate,
                             vals.addedToDirectoryDate].compactMap { $0 }
                guard let date = dates.max(), date > since else { continue }
                let category: FileCategory
                if vals.isDirectory == true {
                    category = .folders
                } else if let type = vals.contentType {
                    category = FileCategory.classify(utType: type)
                } else {
                    category = .other
                }
                out.append(FileItem(url: url, date: date, category: category))
            }
        }
        return out
    }

    private func publish() {
        let snapshot = Array(filteredAll.prefix(shown))
        DispatchQueue.main.async { self.items = snapshot }
    }
}
