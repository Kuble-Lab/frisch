import AppKit
import SwiftUI

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
        if isVisible {
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
    }

    override func cancelOperation(_ sender: Any?) {
        close()
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

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.items) { item in
                        RowView(item: item) { panel?.close() }
                    }
                    if model.items.isEmpty && !model.isLoading {
                        Text("Keine kürzlich benutzten Dateien gefunden.")
                            .foregroundStyle(.secondary)
                            .padding(30)
                    }
                    if model.canLoadMore && !model.items.isEmpty {
                        Button("Ältere laden …") {
                            model.loadMore()
                        }
                        .padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
        }
        .frame(width: 560, height: 620)
    }
}

struct RowView: View {
    let item: FileItem
    var closePanel: () -> Void
    @State private var hovering = false
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
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(hovering ? Color.primary.opacity(0.07) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onDrag {
            // Beide Repräsentationen anbieten: public.file-url (Finder kopiert
            // die Datei) UND Datei-Inhalt (Mail/Slack/Browser hängen sie an).
            let provider = NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
            provider.registerObject(item.url as NSURL, visibility: .all)
            provider.suggestedName = item.name
            return provider
        }
        .onHover { hovering = $0 }
        .onTapGesture {
            NSWorkspace.shared.open(item.url)
            closePanel()
        }
        .contextMenu {
            Button("Öffnen") {
                NSWorkspace.shared.open(item.url)
                closePanel()
            }
            Button("Im Finder zeigen") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
                closePanel()
            }
            ShareLink("Teilen", item: item.url)
        }
    }
}
