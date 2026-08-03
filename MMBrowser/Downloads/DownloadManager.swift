import Foundation
import WebKit

enum DownloadStatus: String, Codable, Equatable {
    case downloading
    case completed
    case failed
    case cancelled
}

struct DownloadItem: Codable, Equatable, Identifiable {
    let id: UUID
    var fileName: String
    var sourceURL: String
    var savedAt: Date
    var status: DownloadStatus
    var bytesWritten: Int64
    var totalBytes: Int64
    var errorMessage: String?
    var mimeType: String?

    var fileURL: URL {
        DownloadManager.directory.appendingPathComponent(fileName)
    }

    var progress: Double {
        guard totalBytes > 0 else { return status == .completed ? 1 : 0 }
        return min(1, Double(bytesWritten) / Double(totalBytes))
    }

    var isActive: Bool { status == .downloading }

    var displayDetail: String {
        switch status {
        case .downloading:
            if totalBytes > 0 {
                return "\(Self.formatBytes(bytesWritten)) / \(Self.formatBytes(totalBytes))"
            }
            return bytesWritten > 0 ? Self.formatBytes(bytesWritten) : "Downloading…"
        case .completed:
            return sourceURL
        case .failed:
            return errorMessage ?? "Download failed"
        case .cancelled:
            return "Cancelled"
        }
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

/// Browser downloads: progress, cancel/retry, cookie-aware requests, unique filenames.
/// Uses a background URLSession so transfers can finish after the app leaves the foreground.
final class DownloadManager: NSObject {
    static let shared = DownloadManager()
    static let didChangeNotification = Notification.Name("mmbrowser.downloads.changed")
    static let didFinishNotification = Notification.Name("mmbrowser.downloads.finished")
    static let backgroundSessionIdentifier = "com.mmbrowser.downloads"

    private let key = "mmbrowser.downloads.v2"
    private let legacyKey = "mmbrowser.downloads"
    private(set) var items: [DownloadItem] = []

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionIdentifier)
        config.waitsForConnectivity = true
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.timeoutIntervalForResource = 60 * 60 * 6
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()

    private var tasks: [UUID: URLSessionDownloadTask] = [:]
    private var taskIDToItem: [Int: UUID] = [:]
    private var backgroundCompletionHandler: (() -> Void)?

    static var directory: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Extensions treated as downloads when linked / addressed.
    static let fileExtensions: Set<String> = [
        "pdf", "zip", "rar", "7z", "gz", "tar",
        "dmg", "pkg", "ipa", "apk",
        "png", "jpg", "jpeg", "gif", "webp", "heic", "svg",
        "mp3", "m4a", "wav", "aac", "flac",
        "mp4", "mov", "m4v", "webm",
        "csv", "txt", "json", "xml", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
        "pages", "numbers", "key"
    ]

    private static let downloadMIMEPrefixes = [
        "application/pdf",
        "application/zip",
        "application/x-zip",
        "application/x-rar",
        "application/gzip",
        "application/x-gzip",
        "application/octet-stream",
        "application/msword",
        "application/vnd.",
        "application/x-apple-diskimage",
        "application/x-bzip",
        "application/x-7z",
        "audio/",
        "video/",
        "image/"
    ]

    private override init() {
        super.init()
        load()
        // Touch session so outstanding background tasks reconnect, then reconcile.
        _ = session
        session.getAllTasks { [weak self] all in
            guard let self else { return }
            var liveIDs = Set<UUID>()
            for task in all {
                guard let desc = task.taskDescription,
                      let id = UUID(uuidString: desc),
                      let download = task as? URLSessionDownloadTask else { continue }
                self.tasks[id] = download
                self.taskIDToItem[download.taskIdentifier] = id
                liveIDs.insert(id)
            }
            var changed = false
            for i in self.items.indices where self.items[i].status == .downloading {
                if !liveIDs.contains(self.items[i].id) {
                    self.items[i].status = .failed
                    self.items[i].errorMessage = "Interrupted"
                    changed = true
                }
            }
            if changed {
                self.save()
                self.notify()
            }
        }
    }

    /// Called from AppDelegate when the system relaunches the app for background downloads.
    func handleEventsForBackgroundURLSession(completionHandler: @escaping () -> Void) {
        backgroundCompletionHandler = completionHandler
        _ = session
    }

    // MARK: - Public API

    @discardableResult
    func start(
        url: URL,
        suggestedName: String? = nil,
        mimeType: String? = nil,
        cookies: [HTTPCookie] = []
    ) -> DownloadItem {
        let baseName = Self.sanitizeFileName(
            suggestedName?.nilIfEmpty
                ?? Self.fileNameFromContentDisposition(nil)
                ?? url.lastPathComponent.nilIfEmpty
                ?? "download"
        )
        let unique = Self.uniqueFileName(baseName, in: Self.directory, excluding: items)
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        if !cookies.isEmpty {
            let header = HTTPCookie.requestHeaderFields(with: cookies)
            for (k, v) in header {
                request.setValue(v, forHTTPHeaderField: k)
            }
        }

        var item = DownloadItem(
            id: UUID(),
            fileName: unique,
            sourceURL: url.absoluteString,
            savedAt: Date(),
            status: .downloading,
            bytesWritten: 0,
            totalBytes: -1,
            errorMessage: nil,
            mimeType: mimeType
        )
        items.insert(item, at: 0)
        save()
        notify()

        DownloadLocalNotifications.shared.requestAuthorizationIfNeeded()

        let task = session.downloadTask(with: request)
        task.taskDescription = item.id.uuidString
        tasks[item.id] = task
        taskIDToItem[task.taskIdentifier] = item.id
        task.resume()
        return item
    }

    /// Convenience: pull cookies from a web view's store for the download URL host.
    func start(url: URL, suggestedName: String?, mimeType: String?, from webView: WKWebView?, completion: ((DownloadItem) -> Void)? = nil) {
        let store = webView?.configuration.websiteDataStore.httpCookieStore
        guard let store else {
            let item = start(url: url, suggestedName: suggestedName, mimeType: mimeType, cookies: [])
            completion?(item)
            return
        }
        store.getAllCookies { [weak self] all in
            guard let self else { return }
            let host = url.host?.lowercased() ?? ""
            let matched = all.filter { cookie in
                let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                return host == domain || host.hasSuffix("." + domain) || host.hasSuffix(cookie.domain.lowercased())
            }
            DispatchQueue.main.async {
                let item = self.start(url: url, suggestedName: suggestedName, mimeType: mimeType, cookies: matched)
                completion?(item)
            }
        }
    }

    func cancel(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        tasks[id]?.cancel()
        tasks[id] = nil
        items[index].status = .cancelled
        items[index].errorMessage = "Cancelled"
        save()
        notify()
    }

    func retry(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              let url = URL(string: items[index].sourceURL) else { return }
        let old = items[index]
        // Remove failed/cancelled entry then start fresh (keeps history cleaner).
        if old.status == .downloading {
            cancel(id: id)
        }
        removeMetadataOnly(id: id, deleteFile: old.status != .completed)
        start(url: url, suggestedName: old.fileName, mimeType: old.mimeType, from: nil)
    }

    func remove(id: UUID) {
        if let item = items.first(where: { $0.id == id }) {
            if item.status == .downloading {
                tasks[item.id]?.cancel()
                tasks[item.id] = nil
            }
            try? FileManager.default.removeItem(at: item.fileURL)
        }
        items.removeAll { $0.id == id }
        save()
        notify()
    }

    func item(id: UUID) -> DownloadItem? {
        items.first { $0.id == id }
    }

    // MARK: - Classification helpers

    static func isLikelyDownloadURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return !ext.isEmpty && fileExtensions.contains(ext)
    }

    /// Archive / installer MIME types that should never render inline.
    private static let forceDownloadMIMEPrefixes = [
        "application/zip",
        "application/x-zip",
        "application/x-rar",
        "application/gzip",
        "application/x-gzip",
        "application/x-apple-diskimage",
        "application/x-bzip",
        "application/x-7z",
        "application/vnd.android.package-archive",
        "application/x-msdownload",
        "application/octet-stream"
    ]

    private static let archiveExtensions: Set<String> = [
        "zip", "rar", "7z", "gz", "tar", "dmg", "pkg", "ipa", "apk", "exe", "msi"
    ]

    static func shouldDownload(response: URLResponse, isForMainFrame: Bool) -> Bool {
        guard let http = response as? HTTPURLResponse else { return false }
        guard (200..<400).contains(http.statusCode) else { return false }
        let mime = (http.mimeType ?? response.mimeType ?? "").lowercased()
        if mime.hasPrefix("text/html") || mime.hasPrefix("application/xhtml") {
            return false
        }
        if mime.hasPrefix("text/css") || mime.hasPrefix("application/javascript")
            || mime.hasPrefix("text/javascript") || mime.hasPrefix("application/json") {
            return false
        }

        if let disposition = http.value(forHTTPHeaderField: "Content-Disposition")?.lowercased(),
           disposition.contains("attachment") {
            return true
        }

        let url = http.url ?? response.url
        let ext = url?.pathExtension.lowercased() ?? ""

        // Archives / installers: always download (WebKit cannot usefully display them).
        if forceDownloadMIMEPrefixes.contains(where: { mime.hasPrefix($0) })
            || archiveExtensions.contains(ext) {
            return true
        }

        // Main frame: keep PDF / images / media inline unless Content-Disposition said attachment.
        if isForMainFrame {
            return false
        }

        // Subframe / iframe resource hits for downloadable MIME types.
        if downloadMIMEPrefixes.contains(where: { mime.hasPrefix($0) }) {
            return true
        }
        if let url, isLikelyDownloadURL(url) {
            return true
        }
        return false
    }

    static func suggestedFileName(from response: URLResponse?, url: URL) -> String {
        if let http = response as? HTTPURLResponse,
           let name = fileNameFromContentDisposition(http.value(forHTTPHeaderField: "Content-Disposition")) {
            return sanitizeFileName(name)
        }
        if let suggested = response?.suggestedFilename, !suggested.isEmpty {
            return sanitizeFileName(suggested)
        }
        let last = url.lastPathComponent
        if !last.isEmpty && last != "/" { return sanitizeFileName(last) }
        return "download"
    }

    // MARK: - Persistence

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([DownloadItem].self, from: data) {
            items = decoded
            return
        }
        // Migrate v1 items (no status fields).
        if let data = UserDefaults.standard.data(forKey: legacyKey),
           let legacy = try? JSONDecoder().decode([LegacyDownloadItem].self, from: data) {
            items = legacy.map {
                DownloadItem(
                    id: $0.id,
                    fileName: $0.fileName,
                    sourceURL: $0.sourceURL,
                    savedAt: $0.savedAt,
                    status: .completed,
                    bytesWritten: 0,
                    totalBytes: -1,
                    errorMessage: nil,
                    mimeType: nil
                )
            }
            save()
            UserDefaults.standard.removeObject(forKey: legacyKey)
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private func notifyFinish(_ item: DownloadItem) {
        NotificationCenter.default.post(
            name: Self.didFinishNotification,
            object: self,
            userInfo: ["item": item]
        )
        DownloadLocalNotifications.shared.postFinished(item)
    }

    private func updateItem(id: UUID, _ mutate: (inout DownloadItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[index])
        save()
        notify()
    }

    private func removeMetadataOnly(id: UUID, deleteFile: Bool) {
        if deleteFile, let item = items.first(where: { $0.id == id }) {
            try? FileManager.default.removeItem(at: item.fileURL)
        }
        items.removeAll { $0.id == id }
        save()
        notify()
    }

    // MARK: - Naming

    static func sanitizeFileName(_ raw: String) -> String {
        var name = raw.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "download" }
        if name.count > 180 { name = String(name.prefix(180)) }
        return name
    }

    static func uniqueFileName(_ preferred: String, in directory: URL, excluding existing: [DownloadItem]) -> String {
        let ns = preferred as NSString
        let base = ns.deletingPathExtension
        let ext = ns.pathExtension
        var candidate = preferred
        var index = 1
        let taken = Set(existing.map(\.fileName))
        while taken.contains(candidate)
                || FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            if ext.isEmpty {
                candidate = "\(base) (\(index))"
            } else {
                candidate = "\(base) (\(index)).\(ext)"
            }
            index += 1
        }
        return candidate
    }

    static func fileNameFromContentDisposition(_ header: String?) -> String? {
        guard let header, !header.isEmpty else { return nil }
        // filename*=UTF-8''...
        if let star = header.range(of: "filename*=", options: .caseInsensitive) {
            var value = String(header[star.upperBound...])
            if let semi = value.firstIndex(of: ";") { value = String(value[..<semi]) }
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if let tick = value.range(of: "''") {
                value = String(value[tick.upperBound...])
            }
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if let decoded = value.removingPercentEncoding, !decoded.isEmpty {
                return decoded
            }
        }
        if let range = header.range(of: "filename=", options: .caseInsensitive) {
            var value = String(header[range.upperBound...])
            if let semi = value.firstIndex(of: ";") { value = String(value[..<semi]) }
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if !value.isEmpty { return value }
        }
        return nil
    }
}

private struct LegacyDownloadItem: Codable {
    let id: UUID
    var fileName: String
    var sourceURL: String
    var savedAt: Date
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let id = itemID(for: downloadTask) else { return }
        updateItem(id: id) { item in
            item.bytesWritten = totalBytesWritten
            item.totalBytes = totalBytesExpectedToWrite
            item.status = .downloading
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let id = itemID(for: downloadTask),
              let index = items.firstIndex(where: { $0.id == id }) else {
            try? FileManager.default.removeItem(at: location)
            return
        }

        let response = downloadTask.response
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 200
        if !(200..<300).contains(status) {
            try? FileManager.default.removeItem(at: location)
            items[index].status = .failed
            items[index].errorMessage = "HTTP \(status)"
            tasks[id] = nil
            taskIDToItem[downloadTask.taskIdentifier] = nil
            save()
            notify()
            notifyFinish(items[index])
            return
        }

        // Prefer server filename when we only had a generic placeholder name.
        let currentExt = (items[index].fileName as NSString).pathExtension
        let suggested = Self.suggestedFileName(
            from: response,
            url: URL(string: items[index].sourceURL) ?? items[index].fileURL
        )
        let suggestedExt = (suggested as NSString).pathExtension
        let shouldRename = items[index].fileName == "download"
            || (currentExt.isEmpty && !suggestedExt.isEmpty)
        if shouldRename, suggested != items[index].fileName {
            let unique = Self.uniqueFileName(suggested, in: Self.directory, excluding: items.filter { $0.id != id })
            items[index].fileName = unique
        }

        let dest = items[index].fileURL
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: location, to: dest)
            let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path)
            let size = (attrs?[.size] as? NSNumber)?.int64Value ?? items[index].bytesWritten
            items[index].status = .completed
            items[index].bytesWritten = size
            items[index].totalBytes = size
            items[index].errorMessage = nil
            items[index].savedAt = Date()
            if let mime = http?.mimeType ?? response?.mimeType {
                items[index].mimeType = mime
            }
        } catch {
            items[index].status = .failed
            items[index].errorMessage = error.localizedDescription
            try? FileManager.default.removeItem(at: location)
        }

        let finished = items[index]
        tasks[id] = nil
        taskIDToItem[downloadTask.taskIdentifier] = nil
        save()
        notify()
        notifyFinish(finished)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        guard let id = itemID(for: task) else { return }
        updateItem(id: id) { item in
            if item.status == .downloading {
                item.status = .failed
                item.errorMessage = error.localizedDescription
            }
        }
        if let finished = item(id: id) {
            notifyFinish(finished)
        }
        tasks[id] = nil
        taskIDToItem[task.taskIdentifier] = nil
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let handler = backgroundCompletionHandler
        backgroundCompletionHandler = nil
        DispatchQueue.main.async {
            handler?()
        }
    }

    private func itemID(for task: URLSessionTask) -> UUID? {
        if let id = taskIDToItem[task.taskIdentifier] { return id }
        if let desc = task.taskDescription, let id = UUID(uuidString: desc) {
            taskIDToItem[task.taskIdentifier] = id
            return id
        }
        return nil
    }
}
