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
    @Published var isRefreshing = false

    private var query: NSMetadataQuery?
    private var all: [FileItem] = []
    private var spotlightCache: [FileItem] = []
    private var manualCache: [FileItem] = []
    private lazy var folderScanner = FolderScanner { [weak self] files in
        self?.manualCache = files
        self?.mergeAndPublish()
    }
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

    private let mergeQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()
    private var mergeGeneration = 0

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(filterChanged),
                                               name: .frischFilterChanged, object: nil)
    }

    @objc private func filterChanged() {
        publish()
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

    // Manuelle Aktualisierung (Button/⌘R). Zwei Schritte, weil eine Quelle
    // allein nicht reicht: der Ordner-Scan zeigt neue Dateien sofort, auch
    // wenn Spotlight sie noch nicht indexiert hat; der Query-Neustart holt
    // frisch Indexiertes ausserhalb der drei beobachteten Ordner, das die
    // laufende Query sonst erst mit ihrem nächsten Update meldet.
    // Muss auf dem Main-Thread laufen (isRefreshing/isLoading sind @Published).
    func manualRefresh() {
        guard !isRefreshing else { return } // Mehrfachklicks: ein Lauf genügt
        isRefreshing = true
        FrischLog.write("Manuelle Aktualisierung angefordert")
        enqueueRemerge()
        // Läuft schon ein Gathering, wäre ein Neustart nur Arbeit: es
        // publiziert ohnehin gleich und finge sonst von vorne an.
        if !isLoading { run() }
        // Spinner kurz stehen lassen: der Ordner-Scan ist oft in Millisekunden
        // fertig, ein Aufblitzen wirkt wie «nichts passiert».
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.isRefreshing = false
        }
    }

    // Eigene Queues pro Ordner: auch ein langsamer Documents-Scan darf den
    // Screenshot-Ordner nicht aufhalten. Ergebnisse kommen auf dem Main-Thread.
    private func enqueueRemerge() {
        folderScanner.refresh(windowDays: windowDays)
    }

    func loadMore() {
        shown += page
        if shown > filteredAll.count && windowDays < maxWindowDays {
            windowDays = min(windowDays * 4, maxWindowDays)
            run()
        } else {
            publish()
        }
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
        enqueueRemerge()
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
        guard let q = note.object as? NSMetadataQuery else { return }
        process(q, limit: 800)
    }

    @objc private func queryUpdated(_ note: Notification) {
        guard let q = note.object as? NSMetadataQuery else { return }
        process(q)
    }

    @objc private func gatherDone(_ note: Notification) {
        guard let q = note.object as? NSMetadataQuery else { return }
        process(q)
        let count = q.resultCount
        DispatchQueue.main.async {
            guard self.query === q else { return }
            FrischLog.write("Gathering fertig: \(count) Spotlight-Resultate")
            self.isLoading = false
        }
    }

    private func process(_ q: NSMetadataQuery, limit: Int = .max) {
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
        let snapshot = out
        DispatchQueue.main.async {
            // Ein inzwischen ersetzter Query-Lauf darf keinen neueren Stand
            // überschreiben. Alle Caches und UI-Zustände gehören dem Main-Thread.
            guard self.query === q else { return }
            self.spotlightCache = snapshot
            self.mergeAndPublish()
        }
    }

    private func mergeAndPublish() {
        // Auch Dedupe/Sortieren grosser Spotlight-Snapshots gehört nicht auf
        // den UI-Thread. Wartende Zwischenstände durch den neuesten ersetzen.
        mergeGeneration += 1
        let generation = mergeGeneration
        let spotlight = spotlightCache
        let manual = manualCache
        mergeQueue.cancelAllOperations()
        mergeQueue.addOperation {
            var byPath: [String: FileItem] = [:]
            for item in spotlight + manual {
                let path = item.url.path
                if let previous = byPath[path], previous.date >= item.date { continue }
                byPath[path] = item
            }
            let merged = byPath.values.sorted {
                $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date
            }
            DispatchQueue.main.async {
                guard self.mergeGeneration == generation else { return }
                self.all = merged
                self.publish()
            }
        }
    }

    private func publish() {
        let snapshot = Array(filteredAll.prefix(shown))
        items = snapshot
    }
}
