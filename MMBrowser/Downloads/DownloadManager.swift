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
            return Self.downloadingStatusText(bytesWritten: bytesWritten, totalBytes: totalBytes)
        case .completed:
            return sourceURL
        case .failed:
            return errorMessage ?? "Download failed"
        case .cancelled:
            return "Cancelled"
        }
    }

    /// e.g. `12.3 MB / 120 MB · 10%` or `12.3 MB downloaded` when total unknown.
    static func downloadingStatusText(bytesWritten: Int64, totalBytes: Int64) -> String {
        let written = formatBytes(max(0, bytesWritten))
        if totalBytes > 0 {
            let total = formatBytes(totalBytes)
            let pct = Int(min(1, Double(bytesWritten) / Double(totalBytes)) * 100)
            return "\(written) / \(total) · \(pct)%"
        }
        if bytesWritten > 0 {
            return "\(written) downloaded"
        }
        return "Downloading…"
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
    /// HLS packager jobs (multi-step; not URLSessionDownloadTask).
    private var hlsJobs: Set<UUID> = []
    private let hlsStateLock = NSLock()
    private var hlsCancelFlags: [UUID: Bool] = [:]
    private var backgroundCompletionHandler: (() -> Void)?
    private var lastProgressSaveTime: CFAbsoluteTime = 0
    private var lastProgressNotifyTime: CFAbsoluteTime = 0
    private let progressSaveInterval: TimeInterval = 0.5
    private let progressNotifyInterval: TimeInterval = 0.1
    private let hlsQueue = DispatchQueue(label: "com.mmbrowser.hls-offline", qos: .utility)

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
        cookies: [HTTPCookie] = [],
        extraHeaders: [String: String] = [:]
    ) -> DownloadItem {
        let baseName = Self.sanitizeFileName(
            suggestedName?.nilIfEmpty
                ?? Self.fileNameFromContentDisposition(nil)
                ?? url.lastPathComponent.nilIfEmpty
                ?? "download"
        )
        let unique = Self.uniqueFileName(baseName, in: Self.directory, excluding: items)
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        for (k, v) in extraHeaders {
            request.setValue(v, forHTTPHeaderField: k)
        }
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

        let offlineName = unique.lowercased()
        let mediaKind: String = {
            if offlineName.hasSuffix(".m3u8") { return "hls" }
            if offlineName.hasSuffix(".mp4") || offlineName.hasPrefix("video-") { return "video" }
            if offlineName.hasSuffix(".mp3") || offlineName.hasSuffix(".m4a") { return "audio" }
            if Self.needsMediaHeaders(for: url) { return "media" }
            return "file"
        }()
        AppAnalytics.logDownloadStart(mediaKind: mediaKind, host: AppAnalytics.privacyHost(url))

        if Self.needsMediaHeaders(for: url)
            || offlineName.hasPrefix("video-")
            || offlineName.hasSuffix(".mp4")
            || offlineName.hasSuffix(".m3u8") {
            PageMediaProbe.log("dl.request", [
                "id": item.id.uuidString,
                "file": unique,
                "cookieCount": cookies.count,
                "cookieDomains": Array(Set(cookies.map(\.domain))).sorted().joined(separator: ","),
                "hasReferer": request.value(forHTTPHeaderField: "Referer") != nil,
                "hasOrigin": request.value(forHTTPHeaderField: "Origin") != nil,
                "uaPrefix": String((request.value(forHTTPHeaderField: "User-Agent") ?? "").prefix(48)),
                "url": url.absoluteString
            ])
        }

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
        let pageURL = webView?.url?.absoluteString
        let headers = Self.defaultExtraHeaders(for: url, pageURL: pageURL)
        guard let store else {
            let item = start(url: url, suggestedName: suggestedName, mimeType: mimeType, cookies: [], extraHeaders: headers)
            completion?(item)
            return
        }
        store.getAllCookies { [weak self] all in
            guard let self else { return }
            let matched = Self.cookies(for: url, from: all, pageURL: pageURL)
            DispatchQueue.main.async {
                let item = self.start(
                    url: url,
                    suggestedName: suggestedName,
                    mimeType: mimeType,
                    cookies: matched,
                    extraHeaders: headers
                )
                completion?(item)
            }
        }
    }

    /// Offline-save path for HLS masters (packages to a progressive MP4).
    @discardableResult
    func startHLSOffline(
        masterURL: URL,
        suggestedName: String?,
        cookies: [HTTPCookie] = [],
        extraHeaders: [String: String] = [:]
    ) -> DownloadItem {
        let baseName = Self.sanitizeFileName(
            suggestedName?.nilIfEmpty
                ?? "video.mp4"
        )
        let unique = Self.uniqueFileName(baseName, in: Self.directory, excluding: items)
        var item = DownloadItem(
            id: UUID(),
            fileName: unique,
            sourceURL: masterURL.absoluteString,
            savedAt: Date(),
            status: .downloading,
            bytesWritten: 0,
            totalBytes: -1,
            errorMessage: nil,
            mimeType: "video/mp4"
        )
        items.insert(item, at: 0)
        save()
        notify()
        hlsJobs.insert(item.id)
        hlsStateLock.lock()
        hlsCancelFlags[item.id] = false
        hlsStateLock.unlock()
        DownloadLocalNotifications.shared.requestAuthorizationIfNeeded()

        var headers: [String: String] = [:]
        for (k, v) in extraHeaders { headers[k] = v }
        if headers["Referer"] == nil || headers["Origin"] == nil {
            let fallback = Self.defaultExtraHeaders(for: masterURL)
            for (k, v) in fallback where headers[k] == nil { headers[k] = v }
        }
        headers["User-Agent"] = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        headers["Accept"] = "*/*"
        if !cookies.isEmpty {
            let cookieHeader = HTTPCookie.requestHeaderFields(with: cookies)
            for (k, v) in cookieHeader { headers[k] = v }
        }

        PageMediaProbe.log("hls.start", [
            "id": item.id.uuidString,
            "file": unique,
            "cookieCount": cookies.count,
            "url": masterURL.absoluteString
        ])

        let itemID = item.id
        let dest = item.fileURL
        hlsQueue.async { [weak self] in
            guard let self else { return }
            do {
                let result = try MediaHLSOfflinePackager.package(
                    masterURL: masterURL,
                    destinationURL: dest,
                    headers: headers,
                    progress: { [weak self] bytes, expected in
                        DispatchQueue.main.async {
                            self?.updateHLSProgress(id: itemID, bytes: bytes, expectedTotal: expected)
                        }
                    },
                    isCancelled: { [weak self] in
                        guard let self else { return true }
                        self.hlsStateLock.lock()
                        defer { self.hlsStateLock.unlock() }
                        return self.hlsCancelFlags[itemID] == true
                    }
                )
                DispatchQueue.main.async {
                    self.finishHLS(id: itemID, result: .success(result))
                }
            } catch {
                DispatchQueue.main.async {
                    self.finishHLS(id: itemID, result: .failure(error))
                }
            }
        }
        return item
    }

    func startHLSOffline(
        masterURL: URL,
        suggestedName: String?,
        from webView: WKWebView?,
        completion: ((DownloadItem) -> Void)? = nil
    ) {
        let store = webView?.configuration.websiteDataStore.httpCookieStore
        let pageURL = webView?.url?.absoluteString
        let headers = Self.defaultExtraHeaders(for: masterURL, pageURL: pageURL)
        guard let store else {
            let item = startHLSOffline(
                masterURL: masterURL,
                suggestedName: suggestedName,
                cookies: [],
                extraHeaders: headers
            )
            completion?(item)
            return
        }
        store.getAllCookies { [weak self] all in
            guard let self else { return }
            let matched = Self.cookies(for: masterURL, from: all, pageURL: pageURL)
            DispatchQueue.main.async {
                let item = self.startHLSOffline(
                    masterURL: masterURL,
                    suggestedName: suggestedName,
                    cookies: matched,
                    extraHeaders: headers
                )
                completion?(item)
            }
        }
    }

    private func updateHLSProgress(id: UUID, bytes: Int64, expectedTotal: Int64) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              items[index].status == .downloading else { return }
        items[index].bytesWritten = bytes
        if expectedTotal > 0 {
            items[index].totalBytes = max(expectedTotal, bytes)
        }
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastProgressNotifyTime >= progressNotifyInterval {
            lastProgressNotifyTime = now
            notify()
        }
        if now - lastProgressSaveTime >= progressSaveInterval {
            lastProgressSaveTime = now
            save()
        }
    }

    private func finishHLS(id: UUID, result: Swift.Result<MediaHLSOfflinePackager.Result, Error>) {
        hlsJobs.remove(id)
        hlsStateLock.lock()
        hlsCancelFlags[id] = nil
        hlsStateLock.unlock()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        switch result {
        case .success(let packaged):
            if let reason = Self.unplayableMediaFailureReason(
                fileURL: packaged.outputURL,
                mimeType: "video/mp4",
                expectedName: items[index].fileName
            ) {
                PageMediaProbe.log("hls.fail", [
                    "id": id.uuidString,
                    "why": "validate",
                    "reason": reason,
                    "size": packaged.bytesWritten
                ])
                try? FileManager.default.removeItem(at: packaged.outputURL)
                items[index].status = .failed
                items[index].errorMessage = reason
                items[index].bytesWritten = packaged.bytesWritten
            } else {
                items[index].status = .completed
                items[index].bytesWritten = packaged.bytesWritten
                items[index].totalBytes = packaged.bytesWritten
                items[index].errorMessage = nil
                items[index].savedAt = Date()
                items[index].mimeType = "video/mp4"
                var fields = PageMediaProbe.fileProbeSummary(at: items[index].fileURL)
                fields["id"] = id.uuidString
                fields["file"] = items[index].fileName
                PageMediaProbe.log("hls.ok", fields)
            }
        case .failure(let error):
            if items[index].status != .cancelled {
                items[index].status = .failed
                items[index].errorMessage = error.localizedDescription
            }
            try? FileManager.default.removeItem(at: items[index].fileURL)
            PageMediaProbe.log("hls.fail", [
                "id": id.uuidString,
                "why": "error",
                "error": error.localizedDescription
            ])
        }
        save()
        notify()
        notifyFinish(items[index])
    }

    private static func needsMediaHeaders(for url: URL) -> Bool {
        PageMediaProbe.isLikelyMediaURL(url)
    }

    private static func defaultExtraHeaders(for url: URL, pageURL: String? = nil) -> [String: String] {
        guard needsMediaHeaders(for: url) else { return [:] }
        let pair = PageMediaProbe.downloadRefererOrigin(for: url, pageURL: pageURL)
        guard !pair.referer.isEmpty else { return [:] }
        return [
            "Referer": pair.referer,
            "Origin": pair.origin
        ]
    }

    /// Match cookies for the download host plus related page session cookies.
    private static func cookies(for url: URL, from all: [HTTPCookie], pageURL: String? = nil) -> [HTTPCookie] {
        let related: [String] = {
            if needsMediaHeaders(for: url) {
                return PageMediaProbe.relatedCookieHosts(for: url, pageURL: pageURL)
            }
            var hosts = [url.host?.lowercased() ?? ""]
            if let pageURL, let host = URL(string: pageURL)?.host?.lowercased() {
                hosts.append(host)
            }
            return hosts
        }()
        return all.filter { cookie in
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return related.contains { relatedHost in
                relatedHost == domain
                    || relatedHost.hasSuffix("." + domain)
                    || domain.hasSuffix(relatedHost)
                    || relatedHost.hasSuffix(cookie.domain.lowercased())
            }
        }
    }

    func cancel(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        tasks[id]?.cancel()
        tasks[id] = nil
        if hlsJobs.contains(id) {
            hlsStateLock.lock()
            hlsCancelFlags[id] = true
            hlsStateLock.unlock()
        }
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
        let isHLS = url.pathExtension.lowercased() == "m3u8"
            || url.absoluteString.lowercased().contains(".m3u8")
        if isHLS {
            _ = startHLSOffline(masterURL: url, suggestedName: old.fileName, cookies: [], extraHeaders: Self.defaultExtraHeaders(for: url))
        } else {
            start(url: url, suggestedName: old.fileName, mimeType: old.mimeType, from: nil)
        }
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

    /// True when this offline video is already downloading or finished (not failed/cancelled).
    func hasActiveOrCompletedOfflineVideo(matching candidate: PageMediaCandidate) -> Bool {
        let urlKey = PageMediaProbe.urlDedupeKey(for: candidate.url)
        let mediaID = PageMediaProbe.mediaID(from: candidate.url)
        let pageVideoID = PageMediaProbe.videoID(fromPageURL: candidate.pageURL)
            ?? candidate.statusID
        return items.contains { item in
            guard item.status == .downloading || item.status == .completed else { return false }
            if let src = URL(string: item.sourceURL) {
                if PageMediaProbe.urlDedupeKey(for: src) == urlKey { return true }
                if let mediaID, !mediaID.isEmpty,
                   PageMediaProbe.mediaID(from: src) == mediaID || item.sourceURL.contains(mediaID) {
                    return true
                }
            }
            if let pageVideoID, !pageVideoID.isEmpty {
                let name = item.fileName.lowercased()
                let needle = pageVideoID.lowercased()
                if name.contains("-\(needle)-") || name.contains("-\(needle).") {
                    return true
                }
            }
            return false
        }
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

    private func updateItem(
        id: UUID,
        persistImmediately: Bool = true,
        notifyImmediately: Bool = true,
        _ mutate: (inout DownloadItem) -> Void
    ) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[index])
        let now = CFAbsoluteTimeGetCurrent()
        if persistImmediately || (now - lastProgressSaveTime) >= progressSaveInterval {
            lastProgressSaveTime = now
            save()
        }
        if notifyImmediately || (now - lastProgressNotifyTime) >= progressNotifyInterval {
            lastProgressNotifyTime = now
            notify()
        }
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
        // Keep the extension when truncating long names (e.g. x-{status}-{date}.mp4).
        if name.count > 120 {
            let ns = name as NSString
            let ext = ns.pathExtension
            let base = ns.deletingPathExtension
            let maxBase = max(16, 120 - (ext.isEmpty ? 0 : ext.count + 1))
            let trimmedBase = String(base.prefix(maxBase))
            name = ext.isEmpty ? trimmedBase : "\(trimmedBase).\(ext)"
        }
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

    /// Reject HTML/JSON error bodies and CMAF init-only “MP4”s that CDNs return with HTTP 200.
    private static func unplayableMediaFailureReason(fileURL: URL, mimeType: String?, expectedName: String) -> String? {
        let ext = (expectedName as NSString).pathExtension.lowercased()
        let mime = (mimeType ?? "").lowercased()
        let lowerName = expectedName.lowercased()
        let looksLikeSavedVideo = mime.hasPrefix("video/")
            || ["mp4", "mov", "m4v", "webm"].contains(ext)
            || lowerName.hasPrefix("video-")
            || lowerName.hasPrefix("x-")
        guard looksLikeSavedVideo else { return nil }

        let size = ((try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? NSNumber)?.int64Value ?? 0
        // Progressive CDN stubs / init segments are tiny; real clips are much larger.
        if size > 0, size < 64_768 {
            return "Download was only a video stub (incomplete). Try Save again after the video plays."
        }

        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return "Couldn’t read downloaded file"
        }
        defer { try? handle.close() }
        let prefix = handle.readData(ofLength: 64)
        guard prefix.count >= 12 else { return "Downloaded file is empty or truncated" }

        // ISO BMFF / MP4: ....ftyp — also require an `mdat` so we reject init-only CMAF.
        if prefix.count >= 8 {
            let ftyp = prefix.subdata(in: 4..<8)
            if String(data: ftyp, encoding: .ascii) == "ftyp" {
                if mp4ContainsBox(fileURL, type: "mdat") { return nil }
                return "Download was only a video init segment (not playable)"
            }
        }
        // WebM / Matroska EBML header
        if prefix.starts(with: [0x1A, 0x45, 0xDF, 0xA3]) { return nil }

        if let text = String(data: prefix, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            if text.hasPrefix("<!doctype") || text.hasPrefix("<html") || text.hasPrefix("{") || text.hasPrefix("<?xml") {
                return "Download wasn’t a video file (CDN blocked or expired link)"
            }
        }
        if mime.contains("mp4") || ext == "mp4" || expectedName.lowercased().hasPrefix("x-") {
            return "Download wasn’t a valid MP4"
        }
        return nil
    }

    /// Scans the first ~2MB for a top-level ISO-BMFF box type (e.g. `mdat`).
    private static func mp4ContainsBox(_ fileURL: URL, type: String) -> Bool {
        guard type.utf8.count == 4,
              let handle = try? FileHandle(forReadingFrom: fileURL) else { return false }
        defer { try? handle.close() }
        let budget = 2 * 1024 * 1024
        var offset = 0
        while offset < budget {
            handle.seek(toFileOffset: UInt64(offset))
            let header = handle.readData(ofLength: 8)
            guard header.count == 8 else { break }
            let size = beUInt32(header, at: 0)
            let box = String(data: header.subdata(in: 4..<8), encoding: .ascii) ?? ""
            if box == type { return true }
            if size == 1 {
                let large = handle.readData(ofLength: 8)
                guard large.count == 8 else { break }
                let big = beUInt64(large, at: 0)
                guard big >= 16, big <= UInt64(Int.max) else { break }
                offset += Int(big)
            } else if size >= 8 {
                offset += Int(size)
            } else if size == 0 {
                break
            } else {
                break
            }
        }
        return false
    }

    private static func beUInt32(_ data: Data, at: Int) -> UInt32 {
        guard at + 4 <= data.count else { return 0 }
        return (UInt32(data[at]) << 24) | (UInt32(data[at + 1]) << 16)
            | (UInt32(data[at + 2]) << 8) | UInt32(data[at + 3])
    }

    private static func beUInt64(_ data: Data, at: Int) -> UInt64 {
        guard at + 8 <= data.count else { return 0 }
        var value: UInt64 = 0
        for i in 0..<8 { value = (value << 8) | UInt64(data[at + i]) }
        return value
    }

    private func ensurePlayableExtension(for item: inout DownloadItem, mimeType: String?) {
        let ext = (item.fileName as NSString).pathExtension.lowercased()
        guard ext.isEmpty else { return }
        let mime = (mimeType ?? "").lowercased()
        let add: String?
        if mime.contains("mp4") || mime.contains("m4v") { add = "mp4" }
        else if mime.contains("webm") { add = "webm" }
        else if mime.contains("quicktime") { add = "mov" }
        else if item.fileName.lowercased().hasPrefix("x-") { add = "mp4" }
        else { add = nil }
        guard let add else { return }
        let renamed = Self.uniqueFileName(
            "\(item.fileName).\(add)",
            in: Self.directory,
            excluding: items.filter { $0.id != item.id }
        )
        let oldURL = Self.directory.appendingPathComponent(item.fileName)
        let newURL = Self.directory.appendingPathComponent(renamed)
        if FileManager.default.fileExists(atPath: oldURL.path) {
            try? FileManager.default.moveItem(at: oldURL, to: newURL)
        }
        item.fileName = renamed
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
        updateItem(id: id, persistImmediately: false, notifyImmediately: false) { item in
            item.bytesWritten = totalBytesWritten
            if totalBytesExpectedToWrite > 0 {
                item.totalBytes = totalBytesExpectedToWrite
            }
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
        let fname = items[index].fileName.lowercased()
        let isMediaDownload = Self.needsMediaHeaders(for: URL(string: items[index].sourceURL) ?? items[index].fileURL)
            || fname.hasPrefix("video-") || fname.hasSuffix(".mp4") || fname.hasSuffix(".m3u8")
        if isMediaDownload {
            var fields: [String: Any] = [
                "id": id.uuidString,
                "http": status,
                "mime": http?.mimeType ?? response?.mimeType ?? "",
                "len": http?.expectedContentLength ?? -1,
                "file": items[index].fileName,
                "url": items[index].sourceURL
            ]
            if let http {
                fields["contentType"] = http.value(forHTTPHeaderField: "Content-Type") ?? ""
                fields["contentRange"] = http.value(forHTTPHeaderField: "Content-Range") ?? ""
                fields["acceptRanges"] = http.value(forHTTPHeaderField: "Accept-Ranges") ?? ""
            }
            // Peek temp file before move.
            var probe = PageMediaProbe.fileProbeSummary(at: location)
            for (k, v) in probe { fields["tmp_\(k)"] = v }
            PageMediaProbe.log("dl.response", fields)
        }
        if !(200..<300).contains(status) {
            try? FileManager.default.removeItem(at: location)
            items[index].status = .failed
            items[index].errorMessage = "HTTP \(status)"
            if isMediaDownload {
                PageMediaProbe.log("dl.fail", ["id": id.uuidString, "why": "http", "http": status])
            }
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
            let mime = http?.mimeType ?? response?.mimeType ?? items[index].mimeType
            if let reason = Self.unplayableMediaFailureReason(fileURL: dest, mimeType: mime, expectedName: items[index].fileName) {
                if isMediaDownload {
                    var fields = PageMediaProbe.fileProbeSummary(at: dest)
                    fields["id"] = id.uuidString
                    fields["why"] = "validate"
                    fields["reason"] = reason
                    fields["mime"] = mime ?? ""
                    PageMediaProbe.log("dl.fail", fields)
                }
                try? FileManager.default.removeItem(at: dest)
                items[index].status = .failed
                items[index].errorMessage = reason
                items[index].bytesWritten = size
                items[index].totalBytes = size
                if let mime { items[index].mimeType = mime }
            } else {
                items[index].status = .completed
                items[index].bytesWritten = size
                items[index].totalBytes = size
                items[index].errorMessage = nil
                items[index].savedAt = Date()
                if let mime { items[index].mimeType = mime }
                // Ensure video files keep a playable extension.
                ensurePlayableExtension(for: &items[index], mimeType: mime)
                if isMediaDownload {
                    var fields = PageMediaProbe.fileProbeSummary(at: items[index].fileURL)
                    fields["id"] = id.uuidString
                    fields["file"] = items[index].fileName
                    fields["mime"] = items[index].mimeType ?? ""
                    PageMediaProbe.log("dl.ok", fields)
                }
            }
        } catch {
            items[index].status = .failed
            items[index].errorMessage = error.localizedDescription
            if isMediaDownload {
                PageMediaProbe.log("dl.fail", [
                    "id": id.uuidString,
                    "why": "move",
                    "error": error.localizedDescription
                ])
            }
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
