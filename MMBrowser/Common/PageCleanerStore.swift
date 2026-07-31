import Foundation
import UIKit

struct PageCleanerRule: Codable, Equatable {
    let id: UUID
    var host: String
    /// `nil` = domain-wide; otherwise exact URL (fragment stripped).
    var urlString: String?
    var selector: String
    var label: String
    var createdAt: Date
    /// JPEG filename under `PageCleanerStore.previewsDirectory`, if captured.
    var previewFileName: String?

    var isURLScoped: Bool { urlString != nil }

    var previewImage: UIImage? {
        guard let previewFileName else { return nil }
        let url = PageCleanerStore.previewsDirectory.appendingPathComponent(previewFileName)
        return UIImage(contentsOfFile: url.path)
    }
}

final class PageCleanerStore {
    static let shared = PageCleanerStore()

    private let key = "mmbrowser.pagecleaner.rules"
    private let defaults = UserDefaults.standard
    private(set) var items: [PageCleanerRule] = []

    static var previewsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("PageCleanerPreviews", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private init() {
        load()
    }

    static func canonicalURLString(_ url: URL) -> String {
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.fragment = nil
        return comps?.string ?? url.absoluteString
    }

    func rules(matching url: URL) -> [PageCleanerRule] {
        guard let host = url.host?.lowercased() else { return [] }
        let canon = Self.canonicalURLString(url)
        return items.filter { rule in
            guard rule.host.lowercased() == host else { return false }
            if let scoped = rule.urlString {
                return scoped == canon
            }
            return true
        }
    }

    /// Groups rules by host, hosts sorted A→Z, rules newest first.
    func groupedByHost() -> [(host: String, rules: [PageCleanerRule])] {
        let map = Dictionary(grouping: items, by: { $0.host.lowercased() })
        return map.keys.sorted().map { host in
            let rules = (map[host] ?? []).sorted { $0.createdAt > $1.createdAt }
            return (host: host, rules: rules)
        }
    }

    @discardableResult
    func add(
        host: String,
        urlString: String?,
        selector: String,
        label: String,
        previewImage: UIImage? = nil
    ) -> PageCleanerRule? {
        let normalizedHost = host.lowercased()
        let trimmedSelector = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHost.isEmpty, !trimmedSelector.isEmpty else { return nil }

        if items.contains(where: {
            $0.host.lowercased() == normalizedHost
                && $0.urlString == urlString
                && $0.selector == trimmedSelector
        }) {
            return nil
        }

        let id = UUID()
        let previewFileName = Self.savePreview(previewImage, id: id)
        let rule = PageCleanerRule(
            id: id,
            host: normalizedHost,
            urlString: urlString,
            selector: trimmedSelector,
            label: label.isEmpty ? trimmedSelector : label,
            createdAt: Date(),
            previewFileName: previewFileName
        )
        items.insert(rule, at: 0)
        save()
        return rule
    }

    func remove(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        Self.deletePreview(items[index].previewFileName)
        items.remove(at: index)
        save()
    }

    func removeAll(host: String) {
        let normalized = host.lowercased()
        let removed = items.filter { $0.host.lowercased() == normalized }
        guard !removed.isEmpty else { return }
        removed.forEach { Self.deletePreview($0.previewFileName) }
        items.removeAll { $0.host.lowercased() == normalized }
        save()
    }

    func removeAll() {
        guard !items.isEmpty else { return }
        items.forEach { Self.deletePreview($0.previewFileName) }
        items.removeAll()
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([PageCleanerRule].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: key)
        }
        NotificationCenter.default.post(name: .pageCleanerRulesChanged, object: nil)
    }

    @discardableResult
    static func savePreview(_ image: UIImage?, id: UUID) -> String? {
        guard let image,
              let data = image.jpegData(compressionQuality: 0.72) else { return nil }
        let name = id.uuidString + ".jpg"
        let url = previewsDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    static func deletePreview(_ fileName: String?) {
        guard let fileName, !fileName.isEmpty else { return }
        let url = previewsDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }
}

enum PageCleanerPreviewBuilder {
    /// Full viewport snapshot with the cleaned element highlighted (no crop).
    static func makePreview(snapshot: UIImage, normalizedRect: CGRect) -> UIImage? {
        let imageSize = snapshot.size
        guard imageSize.width > 1, imageSize.height > 1 else { return nil }

        var norm = normalizedRect
        if norm.width <= 0 || norm.height <= 0 {
            norm = CGRect(x: 0.35, y: 0.35, width: 0.3, height: 0.12)
        }
        norm.origin.x = min(max(norm.origin.x, 0), 1)
        norm.origin.y = min(max(norm.origin.y, 0), 1)
        norm.size.width = min(max(norm.size.width, 0.02), 1 - norm.origin.x)
        norm.size.height = min(max(norm.size.height, 0.02), 1 - norm.origin.y)

        let element = CGRect(
            x: norm.origin.x * imageSize.width,
            y: norm.origin.y * imageSize.height,
            width: norm.size.width * imageSize.width,
            height: norm.size.height * imageSize.height
        )
        let mark = element.insetBy(dx: -2, dy: -2)
            .intersection(CGRect(origin: .zero, size: imageSize))

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = snapshot.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: imageSize, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            snapshot.draw(at: .zero)

            guard !mark.isNull, mark.width > 0, mark.height > 0 else { return }

            cg.setFillColor(UIColor.systemRed.withAlphaComponent(0.28).cgColor)
            cg.fill(mark)

            cg.setStrokeColor(UIColor.systemRed.cgColor)
            cg.setLineWidth(3)
            cg.stroke(mark)

            let tick: CGFloat = 10
            cg.setLineWidth(3.5)
            cg.setLineCap(.round)
            let corners: [(CGPoint, CGPoint, CGPoint)] = [
                (CGPoint(x: mark.minX, y: mark.minY + tick), CGPoint(x: mark.minX, y: mark.minY), CGPoint(x: mark.minX + tick, y: mark.minY)),
                (CGPoint(x: mark.maxX - tick, y: mark.minY), CGPoint(x: mark.maxX, y: mark.minY), CGPoint(x: mark.maxX, y: mark.minY + tick)),
                (CGPoint(x: mark.minX, y: mark.maxY - tick), CGPoint(x: mark.minX, y: mark.maxY), CGPoint(x: mark.minX + tick, y: mark.maxY)),
                (CGPoint(x: mark.maxX - tick, y: mark.maxY), CGPoint(x: mark.maxX, y: mark.maxY), CGPoint(x: mark.maxX, y: mark.maxY - tick))
            ]
            for (a, b, c) in corners {
                cg.move(to: a)
                cg.addLine(to: b)
                cg.addLine(to: c)
            }
            cg.strokePath()

            let badge = "Hidden"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            let textSize = (badge as NSString).size(withAttributes: attrs)
            let badgeRect = CGRect(
                x: max(4, mark.minX),
                y: max(4, mark.minY - textSize.height - 8),
                width: textSize.width + 10,
                height: textSize.height + 6
            )
            let badgePath = UIBezierPath(roundedRect: badgeRect, cornerRadius: 4)
            UIColor.systemRed.setFill()
            badgePath.fill()
            (badge as NSString).draw(
                in: CGRect(
                    x: badgeRect.minX + 5,
                    y: badgeRect.minY + 3,
                    width: textSize.width,
                    height: textSize.height
                ),
                withAttributes: attrs
            )
        }
    }

    static func normalizedRect(from body: [String: Any]) -> CGRect? {
        guard let rect = body["rect"] as? [String: Any] else { return nil }
        func num(_ key: String) -> CGFloat? {
            if let v = rect[key] as? CGFloat { return v }
            if let v = rect[key] as? Double { return CGFloat(v) }
            if let v = rect[key] as? NSNumber { return CGFloat(truncating: v) }
            return nil
        }
        guard let x = num("x"), let y = num("y"), let w = num("w"), let h = num("h") else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

extension Notification.Name {
    static let pageCleanerRulesChanged = Notification.Name("mmbrowser.pagecleaner.changed")
}
