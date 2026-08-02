import UIKit

/// Disk cache for tab-switcher preview thumbnails (survives relaunch).
enum TabSnapshotStore {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("TabSnapshots", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).jpg")
    }

    static func save(_ image: UIImage, for id: UUID) {
        let thumbnail = scaled(image, maxSide: 480)
        guard let data = thumbnail.jpegData(compressionQuality: 0.72) else { return }
        try? data.write(to: fileURL(for: id), options: .atomic)
    }

    static func load(for id: UUID) -> UIImage? {
        guard let data = try? Data(contentsOf: fileURL(for: id)) else { return nil }
        return UIImage(data: data)
    }

    static func remove(for id: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: id))
    }

    static func removeAll(except keep: Set<UUID> = []) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files where file.pathExtension.lowercased() == "jpg" {
            let name = file.deletingPathExtension().lastPathComponent
            if let id = UUID(uuidString: name), keep.contains(id) { continue }
            try? FileManager.default.removeItem(at: file)
        }
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
