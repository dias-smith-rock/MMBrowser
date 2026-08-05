import UIKit

/// Disk cache for tab-switcher preview thumbnails (survives relaunch).
/// Stores a fast micro thumbnail and a higher-quality standard thumbnail per tab.
enum TabSnapshotStore {
    private static let microMaxSide: CGFloat = 140
    private static let microQuality: CGFloat = 0.45
    private static let standardMaxSide: CGFloat = 480
    private static let standardQuality: CGFloat = 0.72

    private static var directory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("TabSnapshots", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func standardFileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).jpg")
    }

    private static func microFileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).micro.jpg")
    }

    /// Standard-scaled image for in-memory `tab.snapshot` — never retain full WK snapshot pixels.
    static func thumbnailForMemory(_ image: UIImage) -> UIImage {
        scaled(image, maxSide: standardMaxSide)
    }

    static func save(_ image: UIImage, for id: UUID) {
        let micro = scaled(image, maxSide: microMaxSide)
        let standard = scaled(image, maxSide: standardMaxSide)
        if let data = micro.jpegData(compressionQuality: microQuality) {
            try? data.write(to: microFileURL(for: id), options: .atomic)
        }
        if let data = standard.jpegData(compressionQuality: standardQuality) {
            try? data.write(to: standardFileURL(for: id), options: .atomic)
        }
    }

    static func loadMicro(for id: UUID) -> UIImage? {
        guard let data = try? Data(contentsOf: microFileURL(for: id)) else { return nil }
        return UIImage(data: data)
    }

    static func loadStandard(for id: UUID) -> UIImage? {
        guard let data = try? Data(contentsOf: standardFileURL(for: id)) else { return nil }
        return UIImage(data: data)
    }

    /// Backward-compatible alias — returns standard quality when available.
    static func load(for id: UUID) -> UIImage? {
        loadStandard(for: id) ?? loadMicro(for: id)
    }

    static func loadStandardAsync(for id: UUID, completion: @escaping (UIImage?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let image = loadStandard(for: id)
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    static func remove(for id: UUID) {
        try? FileManager.default.removeItem(at: standardFileURL(for: id))
        try? FileManager.default.removeItem(at: microFileURL(for: id))
    }

    static func removeAll(except keep: Set<UUID> = []) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files where file.pathExtension.lowercased() == "jpg" {
            guard let id = tabID(from: file) else { continue }
            if keep.contains(id) { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func tabID(from file: URL) -> UUID? {
        let base = file.deletingPathExtension().lastPathComponent
        if base.hasSuffix(".micro") {
            return UUID(uuidString: String(base.dropLast(6)))
        }
        return UUID(uuidString: base)
    }

    private static func scaled(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxSide, longest > 0 else { return image }
        let scale = maxSide / longest
        let newSize = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
