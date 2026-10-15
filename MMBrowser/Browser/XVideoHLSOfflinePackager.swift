import AVFoundation
import Foundation

/// Downloads an X/Twitter HLS master playlist, pulls fMP4 init+segments for video (and audio if present),
/// then muxes to a single progressive MP4 playable by AVPlayer.
enum XVideoHLSOfflinePackager {
    struct Result {
        let outputURL: URL
        let bytesWritten: Int64
    }

    enum PackagerError: LocalizedError {
        case badPlaylist
        case noVideoVariant
        case emptySegments
        case http(Int)
        case exportFailed(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .badPlaylist: return "Couldn’t parse HLS playlist"
            case .noVideoVariant: return "No downloadable video stream found"
            case .emptySegments: return "HLS playlist had no segments"
            case .http(let code): return "HTTP \(code)"
            case .exportFailed(let msg): return msg
            case .cancelled: return "Cancelled"
            }
        }
    }

    /// - Parameters:
    ///   - progress: called on the calling queue with approximate bytes downloaded.
    ///   - isCancelled: polled between network steps.
    static func package(
        masterURL: URL,
        destinationURL: URL,
        headers: [String: String],
        progress: ((Int64) -> Void)?,
        isCancelled: () -> Bool
    ) throws -> Result {
        let session = makeSession(headers: headers)
        var downloaded: Int64 = 0
        let bump: (Int64) -> Void = { n in
            downloaded += n
            progress?(downloaded)
        }

        try checkCancelled(isCancelled)
        let masterText = try fetchText(masterURL, session: session, bytes: &downloaded, progress: progress)
        XVideoOfflineProbe.log("hls.master", [
            "url": masterURL.absoluteString,
            "bytes": masterText.utf8.count,
            "lines": masterText.split(separator: "\n").count
        ])

        let master = parseMaster(masterText, base: masterURL)
        guard let videoURL = master.bestVideoURL else {
            throw PackagerError.noVideoVariant
        }
        XVideoOfflineProbe.log("hls.variant", [
            "video": videoURL.absoluteString,
            "audio": master.bestAudioURL?.absoluteString ?? "",
            "bandwidth": master.bestBandwidth
        ])

        let workDir = destinationURL.deletingLastPathComponent()
            .appendingPathComponent(".hls-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        try checkCancelled(isCancelled)
        let videoMedia = try fetchText(videoURL, session: session, bytes: &downloaded, progress: progress)
        let videoParts = parseMedia(videoMedia, base: videoURL)
        guard !videoParts.segments.isEmpty || videoParts.mapURI != nil else {
            throw PackagerError.emptySegments
        }
        let videoFile = workDir.appendingPathComponent("video.mp4")
        try concatTrack(parts: videoParts, to: videoFile, session: session, bytes: &downloaded, progress: progress, isCancelled: isCancelled)
        XVideoOfflineProbe.log("hls.videoTrack", XVideoOfflineProbe.fileProbeSummary(at: videoFile))

        var audioFile: URL?
        if let audioURL = master.bestAudioURL {
            try checkCancelled(isCancelled)
            let audioMedia = try fetchText(audioURL, session: session, bytes: &downloaded, progress: progress)
            let audioParts = parseMedia(audioMedia, base: audioURL)
            if !audioParts.segments.isEmpty || audioParts.mapURI != nil {
                let out = workDir.appendingPathComponent("audio.m4a")
                try concatTrack(parts: audioParts, to: out, session: session, bytes: &downloaded, progress: progress, isCancelled: isCancelled)
                audioFile = out
                XVideoOfflineProbe.log("hls.audioTrack", XVideoOfflineProbe.fileProbeSummary(at: out))
            }
        }

        try checkCancelled(isCancelled)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        if let audioFile {
            try muxPassthrough(video: videoFile, audio: audioFile, to: destinationURL, isCancelled: isCancelled)
        } else {
            try FileManager.default.copyItem(at: videoFile, to: destinationURL)
        }

        let size = ((try? FileManager.default.attributesOfItem(atPath: destinationURL.path))?[.size] as? NSNumber)?.int64Value ?? downloaded
        XVideoOfflineProbe.log("hls.packaged", [
            "out": destinationURL.lastPathComponent,
            "size": size,
            "hadAudio": audioFile != nil
        ])
        return Result(outputURL: destinationURL, bytesWritten: size)
    }

    // MARK: - Network

    private static func makeSession(headers: [String: String]) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 60 * 30
        config.httpAdditionalHeaders = headers.isEmpty ? nil : headers
        return URLSession(configuration: config)
    }

    private static func fetchText(
        _ url: URL,
        session: URLSession,
        bytes: inout Int64,
        progress: ((Int64) -> Void)?
    ) throws -> String {
        let data = try fetchData(url, session: session)
        bytes += Int64(data.count)
        progress?(bytes)
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw PackagerError.badPlaylist
        }
        return text
    }

    private static func fetchData(_ url: URL, session: URLSession) throws -> Data {
        let sema = DispatchSemaphore(value: 0)
        var dataOut: Data?
        var errorOut: Error?
        var status = 200
        session.dataTask(with: url) { data, response, error in
            defer { sema.signal() }
            if let error { errorOut = error; return }
            status = (response as? HTTPURLResponse)?.statusCode ?? 200
            dataOut = data
        }.resume()
        sema.wait()
        if let errorOut { throw errorOut }
        guard (200..<300).contains(status) else { throw PackagerError.http(status) }
        guard let dataOut else { throw PackagerError.badPlaylist }
        return dataOut
    }

    private static func concatTrack(
        parts: MediaPlaylist,
        to file: URL,
        session: URLSession,
        bytes: inout Int64,
        progress: ((Int64) -> Void)?,
        isCancelled: () -> Bool
    ) throws {
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }

        var uris: [String] = []
        if let map = parts.mapURI { uris.append(map) }
        uris.append(contentsOf: parts.segments)

        for uri in uris {
            try checkCancelled(isCancelled)
            let url = resolve(uri, relativeTo: parts.baseURL)
            let data = try fetchData(url, session: session)
            handle.write(data)
            bytes += Int64(data.count)
            progress?(bytes)
        }
    }

    // MARK: - Mux

    private static func muxPassthrough(
        video: URL,
        audio: URL,
        to output: URL,
        isCancelled: () -> Bool
    ) throws {
        let videoAsset = AVURLAsset(url: video)
        let audioAsset = AVURLAsset(url: audio)
        let mix = AVMutableComposition()

        guard let vTrack = videoAsset.tracks(withMediaType: .video).first,
              let compV = mix.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            try FileManager.default.copyItem(at: video, to: output)
            return
        }
        let vDuration = videoAsset.duration
        try compV.insertTimeRange(CMTimeRange(start: .zero, duration: vDuration), of: vTrack, at: .zero)

        if let aTrack = audioAsset.tracks(withMediaType: .audio).first,
           let compA = mix.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let aDuration = min(audioAsset.duration, vDuration)
            try? compA.insertTimeRange(CMTimeRange(start: .zero, duration: aDuration), of: aTrack, at: .zero)
        }

        try checkCancelled(isCancelled)

        guard let export = AVAssetExportSession(asset: mix, presetName: AVAssetExportPresetPassthrough)
                ?? AVAssetExportSession(asset: mix, presetName: AVAssetExportPresetHighestQuality) else {
            try FileManager.default.copyItem(at: video, to: output)
            return
        }
        export.outputURL = output
        export.outputFileType = .mp4

        let sema = DispatchSemaphore(value: 0)
        export.exportAsynchronously { sema.signal() }
        sema.wait()

        switch export.status {
        case .completed:
            return
        case .cancelled:
            throw PackagerError.cancelled
        default:
            let msg = export.error?.localizedDescription ?? "Mux export failed"
            XVideoOfflineProbe.log("hls.muxFail", ["error": msg])
            // Fall back to video-only so the user still gets a playable file.
            if FileManager.default.fileExists(atPath: output.path) {
                try? FileManager.default.removeItem(at: output)
            }
            try FileManager.default.copyItem(at: video, to: output)
        }
    }

    // MARK: - Playlist parsing

    private struct MasterPlaylist {
        var bestVideoURL: URL?
        var bestAudioURL: URL?
        var bestBandwidth: Int = 0
    }

    private struct MediaPlaylist {
        var baseURL: URL
        var mapURI: String?
        var segments: [String]
    }

    private static func parseMaster(_ text: String, base: URL) -> MasterPlaylist {
        var result = MasterPlaylist()
        var pendingBandwidth = 0
        var pendingAudioGroup: String?
        var audioGroups: [String: URL] = [:]

        let lines = text.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }
        for line in lines {
            if line.hasPrefix("#EXT-X-MEDIA:") {
                let attrs = parseAttrs(String(line.dropFirst("#EXT-X-MEDIA:".count)))
                guard (attrs["TYPE"] ?? "").uppercased() == "AUDIO",
                      let group = attrs["GROUP-ID"],
                      let uri = attrs["URI"] else { continue }
                audioGroups[group] = resolve(uri, relativeTo: base)
                if (attrs["DEFAULT"] ?? "").uppercased() == "YES" || result.bestAudioURL == nil {
                    result.bestAudioURL = audioGroups[group]
                }
                continue
            }
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                let attrs = parseAttrs(String(line.dropFirst("#EXT-X-STREAM-INF:".count)))
                pendingBandwidth = Int(attrs["BANDWIDTH"] ?? attrs["AVERAGE-BANDWIDTH"] ?? "0") ?? 0
                pendingAudioGroup = attrs["AUDIO"]
                continue
            }
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            // URI line following STREAM-INF
            let url = resolve(line, relativeTo: base)
            let path = url.path.lowercased()
            // Skip pure audio variant rows if mis-tagged.
            if path.contains("/mp4a/") && !path.contains("/avc1/") { continue }
            if pendingBandwidth >= result.bestBandwidth || result.bestVideoURL == nil {
                result.bestBandwidth = pendingBandwidth
                result.bestVideoURL = url
                if let group = pendingAudioGroup, let audio = audioGroups[group] {
                    result.bestAudioURL = audio
                }
            }
            pendingBandwidth = 0
            pendingAudioGroup = nil
        }

        // Master that is already a media playlist (no STREAM-INF).
        if result.bestVideoURL == nil, text.contains("#EXTINF") || text.contains("#EXT-X-MAP") {
            result.bestVideoURL = base
        }
        return result
    }

    private static func parseMedia(_ text: String, base: URL) -> MediaPlaylist {
        var mapURI: String?
        var segments: [String] = []
        let lines = text.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }
        for line in lines {
            if line.hasPrefix("#EXT-X-MAP:") {
                let attrs = parseAttrs(String(line.dropFirst("#EXT-X-MAP:".count)))
                mapURI = attrs["URI"]
                continue
            }
            if line.isEmpty || line.hasPrefix("#") { continue }
            segments.append(line)
        }
        return MediaPlaylist(baseURL: base, mapURI: mapURI, segments: segments)
    }

    private static func parseAttrs(_ raw: String) -> [String: String] {
        var result: [String: String] = [:]
        var i = raw.startIndex
        while i < raw.endIndex {
            while i < raw.endIndex, raw[i] == "," || raw[i].isWhitespace { i = raw.index(after: i) }
            guard i < raw.endIndex else { break }
            guard let eq = raw[i...].firstIndex(of: "=") else { break }
            let key = String(raw[i..<eq]).trimmingCharacters(in: .whitespaces)
            var j = raw.index(after: eq)
            let value: String
            if j < raw.endIndex, raw[j] == "\"" {
                j = raw.index(after: j)
                var end = j
                while end < raw.endIndex, raw[end] != "\"" { end = raw.index(after: end) }
                value = String(raw[j..<end])
                i = end < raw.endIndex ? raw.index(after: end) : end
            } else {
                var end = j
                while end < raw.endIndex, raw[end] != "," { end = raw.index(after: end) }
                value = String(raw[j..<end]).trimmingCharacters(in: .whitespaces)
                i = end
            }
            if !key.isEmpty { result[key] = value }
        }
        return result
    }

    private static func resolve(_ uri: String, relativeTo base: URL) -> URL {
        if let abs = URL(string: uri), abs.scheme != nil { return abs }
        return URL(string: uri, relativeTo: base)?.absoluteURL ?? base
    }

    private static func checkCancelled(_ isCancelled: () -> Bool) throws {
        if isCancelled() { throw PackagerError.cancelled }
    }
}
