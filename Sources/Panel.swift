import AppKit
import SwiftUI
import Quartz

final class FloatingPanel: NSPanel {
    private let model: RecentFilesModel

    init(model: RecentFilesModel) {
        self.model = model
        super.init(contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
                   styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        // WICHTIG: false — sonst verschiebt ein Zieh-Versuch auf einer Zeile
        // das ganze Fenster und der Datei-Drag startet nie.
        isMovableByWindowBackground = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        // Klick in eine andere App deaktiviert Frisch → Panel verschwindet.
        hidesOnDeactivate = true
        contentView = NSHostingView(rootView: PanelView(model: model, panel: self))
    }

    override var canBecomeKey: Bool { true }

    func toggle() {
        // Nur schliessen, wenn das Panel wirklich im Fokus steht. Ein Panel,
        // das «sichtbar», aber nicht key ist (auf dem anderen Bildschirm
        // liegen geblieben, oder nach verweigerter Aktivierung verwaist),
        // würde der erste Druck sonst unsichtbar schliessen — und erst der
        // zweite öffnet es wieder («muss 2x drücken»).
        if isVisible && isKeyWindow {
            close()
        } else {
            show()
        }
    }

    func show() {
        model.refresh()
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            let size = frame.size
            setFrameOrigin(NSPoint(x: f.midX - size.width / 2,
                                   y: f.midY - size.height / 2 + f.height * 0.06))
        }
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Tastatur (Pfeile, Space=Quick Look, Enter=Öffnen) soll sofort in der Liste landen.
        if let table = Self.findTableView(in: contentView) {
            makeFirstResponder(table)
        }
        // Selbstheilung gegen das Aktivierungs-Race neuerer macOS-Versionen
        // (cooperative activation): wird die Aktivierung erst gewährt und
        // gleich wieder entzogen, blendet hidesOnDeactivate das eben gezeigte
        // Panel sofort wieder aus → einmal nachlegen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, !self.isVisible else { return }
            FrischLog.write("Panel nach Öffnen sofort wieder versteckt — zweiter Versuch")
            self.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    private static func findTableView(in view: NSView?) -> NSTableView? {
        guard let view else { return nil }
        if let t = view as? NSTableView { return t }
        for sub in view.subviews {
            if let t = findTableView(in: sub) { return t }
        }
        return nil
    }
}

struct PanelView: View {
    @ObservedObject var model: RecentFilesModel
    weak var panel: NSPanel?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Letzte Dateien")
                    .font(.headline)
                Spacer()
                if model.isLoading {
                    ProgressView().controlSize(.small)
                        .help("Spotlight indexiert noch im Hintergrund")
                }
                Button {
                    (NSApp.delegate as? AppDelegate)?.openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Einstellungen")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Divider()

            ZStack {
                FileTableView(model: model) { panel?.close() }
                if model.items.isEmpty && !model.isLoading {
                    Text("Keine kürzlich benutzten Dateien gefunden.")
                        .foregroundStyle(.secondary)
                        .padding(30)
                }
            }

            if model.canLoadMore && !model.items.isEmpty {
                Divider()
                Button("Ältere laden …") {
                    model.loadMore()
                }
                .padding(.vertical, 8)
            }
        }
        .frame(width: 560, height: 620)
    }
}

// NSTableView statt SwiftUI-Liste: liefert die Mac-Standards, die SwiftUI
// hier nicht kann — Klick=Auswahl, ⇧/⌘-Mehrfachauswahl, Drag aller
// ausgewählten Zeilen, Doppelklick-Aktion und Space→QLPreviewPanel.
struct FileTableView: NSViewRepresentable {
    @ObservedObject var model: RecentFilesModel
    var closePanel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(closePanel: closePanel)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let table = QLTableView()
        table.coordinator = context.coordinator
        context.coordinator.table = table

        let col = NSTableColumn(identifier: .init("file"))
        table.addTableColumn(col)
        table.headerView = nil
        table.rowHeight = 50
        table.allowsMultipleSelection = true
        table.style = .inset
        table.backgroundColor = .clear
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.revealSelected)
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        table.menu = context.coordinator.buildMenu()

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.closePanel = closePanel
        context.coordinator.update(items: model.items)
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate,
                             QLPreviewPanelDataSource, QLPreviewPanelDelegate {
        var closePanel: () -> Void
        weak var table: QLTableView?
        private(set) var items: [FileItem] = []
        private var previewURLs: [URL] = []

        init(closePanel: @escaping () -> Void) {
            self.closePanel = closePanel
        }

        func update(items new: [FileItem]) {
            guard new.map(\.id) != items.map(\.id) else {
                items = new
                return
            }
            // Auswahl über Daten-Updates hinweg per Pfad erhalten.
            let selectedIds = Set((table?.selectedRowIndexes ?? [])
                .compactMap { items.indices.contains($0) ? items[$0].id : nil })
            items = new
            table?.reloadData()
            if !selectedIds.isEmpty {
                let idx = IndexSet(new.enumerated()
                    .filter { selectedIds.contains($0.element.id) }
                    .map(\.offset))
                table?.selectRowIndexes(idx, byExtendingSelection: false)
            }
        }

        // MARK: Auswahl

        func selectedURLs() -> [URL] {
            guard let table else { return [] }
            var rows = table.selectedRowIndexes
            if let clicked = table.clickedRowIfValid, !rows.contains(clicked) {
                rows = [clicked]
            }
            return rows.compactMap { items.indices.contains($0) ? items[$0].url : nil }
        }

        // MARK: Aktionen

        @objc func openSelected() {
            let urls = selectedURLs()
            guard !urls.isEmpty else { return }
            for url in urls { NSWorkspace.shared.open(url) }
            closePanel()
        }

        @objc func revealSelected() {
            let urls = selectedURLs()
            guard !urls.isEmpty else { return }
            NSWorkspace.shared.activateFileViewerSelecting(urls)
            closePanel()
        }

        @objc func quickLookSelected() {
            togglePreview()
        }

        func buildMenu() -> NSMenu {
            let m = NSMenu()
            for (title, action) in [("Öffnen", #selector(openSelected)),
                                    ("Im Finder zeigen", #selector(revealSelected)),
                                    ("Quick Look", #selector(quickLookSelected))] {
                let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
                item.target = self
                m.addItem(item)
            }
            return m
        }

        // MARK: Quick Look

        func togglePreview() {
            guard let panel = QLPreviewPanel.shared() else { return }
            if panel.isVisible {
                panel.orderOut(nil)
            } else {
                previewURLs = selectedURLs()
                guard !previewURLs.isEmpty else { return }
                panel.makeKeyAndOrderFront(nil)
            }
        }

        func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
            previewURLs.count
        }

        func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
            previewURLs[index] as NSURL
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            if QLPreviewPanel.sharedPreviewPanelExists(),
               QLPreviewPanel.shared().isVisible {
                previewURLs = selectedURLs()
                QLPreviewPanel.shared().reloadData()
            }
        }

        // MARK: Tabelle

        func numberOfRows(in tableView: NSTableView) -> Int {
            items.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard items.indices.contains(row) else { return nil }
            return NSHostingView(rootView: RowView(item: items[row], closePanel: closePanel))
        }

        // Drag & Drop: startet der Drag auf einer ausgewählten Zeile,
        // zieht NSTableView automatisch ALLE ausgewählten Zeilen mit.
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard items.indices.contains(row) else { return nil }
            return items[row].url as NSURL
        }
    }
}

final class QLTableView: NSTableView {
    weak var coordinator: FileTableView.Coordinator?

    var clickedRowIfValid: Int? {
        clickedRow >= 0 ? clickedRow : nil
    }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            coordinator?.togglePreview()
        } else if event.keyCode == 36 || event.keyCode == 76 { // Return / Enter
            coordinator?.openSelected()
        } else {
            super.keyDown(with: event)
        }
    }

    // QLPreviewPanel sucht seinen Controller über die Responder-Chain.
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = coordinator
        panel.delegate = coordinator
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {}
}

struct RowView: View {
    let item: FileItem
    var closePanel: () -> Void
    @State private var thumbnail: NSImage?

    init(item: FileItem, closePanel: @escaping () -> Void) {
        self.item = item
        self.closePanel = closePanel
    }

    private static let relFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    private var folderDisplay: String {
        let parent = item.url.deletingLastPathComponent().path
        let home = NSHomeDirectory()
        return parent.hasPrefix(home) ? "~" + parent.dropFirst(home.count) : parent
    }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                        .resizable()
                        .frame(width: 32, height: 32)
                }
            }
            .frame(width: 40, height: 40)
            .onAppear {
                if thumbnail == nil {
                    ThumbnailLoader.shared.load(for: item.url) { thumbnail = $0 }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).lineLimit(1)
                Text(folderDisplay)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(Self.relFormatter.localizedString(for: item.date, relativeTo: Date()))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
                closePanel()
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Im Finder zeigen")
            ShareLink(item: item.url) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .help("Teilen")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
    }
}
