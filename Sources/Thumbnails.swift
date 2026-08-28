import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

final class ThumbnailLoader {
    static let shared = ThumbnailLoader()
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 600
    }

    static func isPreviewable(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .movie)
            || type.conforms(to: .pdf) || type.conforms(to: .audiovisualContent)
    }

    func cached(for url: URL) -> NSImage? {
        cache.object(forKey: url.path as NSString)
    }

    func load(for url: URL, completion: @escaping (NSImage) -> Void) {
        if let img = cached(for: url) {
            completion(img)
            return
        }
        guard Self.isPreviewable(url) else { return }
        let request = QLThumbnailGenerator.Request(fileAt: url,
                                                  size: CGSize(width: 80, height: 80),
                                                  scale: 2,
                                                  representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] rep, _ in
            guard let self, let rep else { return }
            let img = NSImage(cgImage: rep.cgImage,
                              size: NSSize(width: rep.cgImage.width / 2, height: rep.cgImage.height / 2))
            DispatchQueue.main.async {
                self.cache.setObject(img, forKey: url.path as NSString)
                completion(img)
            }
        }
    }
}
