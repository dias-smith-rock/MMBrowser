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
    ///   - progress: `(downloadedBytes, expectedTotalBytes)`; `expectedTotalBytes` is `-1` until estimated.
    ///   - isCancelled: polled between network steps.
    static func package(
        masterURL: URL,
        destinationURL: URL,
        headers: [String: String],
        progress: ((Int64, Int64) -> Void)?,
        isCancelled: () -> Bool
    ) throws -> Result {
        let session = makeSession(headers: headers)
        let tally = ByteTally()
        let report: () -> Void = {
            if tally.expectedTotal > 0 {
                tally.expectedTotal = max(tally.expectedTotal, tally.downloaded)
            }
            progress?(tally.downloaded, tally.expectedTotal)
        }
        let noteBytes: (Int64) -> Void = { count in
            tally.downloaded += count
            report()
        }

        try checkCancelled(isCancelled)
        let (masterText, masterBytes) = try fetchText(masterURL, session: session)
        noteBytes(masterBytes)
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
        let (videoMedia, videoPlaylistBytes) = try fetchText(videoURL, session: session)
        noteBytes(videoPlaylistBytes)
        let videoParts = parseMedia(videoMedia, base: videoURL)
        guard !videoParts.segments.isEmpty || videoParts.mapURI != nil else {
            throw PackagerError.emptySegments
        }
        var estimated = estimateBytes(for: videoParts, bandwidth: master.bestBandwidth)
        if master.bestAudioURL != nil, videoParts.totalDuration > 0 {
            // Rough audio overhead before its playlist is fetched.
            let audioBW = max(96_000, master.bestBandwidth / 10)
            estimated += Int64(videoParts.totalDuration * Double(audioBW) / 8.0)
        }
        if estimated > 0 {
            tally.expectedTotal = max(estimated, tally.downloaded)
            report()
        }
        let videoIsTS = videoParts.looksLikeMPEGTS
        let videoFile = workDir.appendingPathComponent(videoIsTS ? "video.ts" : "video.mp4")
        try concatTrack(
            parts: videoParts,
            to: videoFile,
            session: session,
            onChunk: noteBytes,
            isCancelled: isCancelled
        )
        XVideoOfflineProbe.log("hls.videoTrack", {
            var f = XVideoOfflineProbe.fileProbeSummary(at: videoFile)
            f["container"] = videoIsTS ? "ts" : "fmp4"
            return f
        }())

        var audioFile: URL?
        if let audioURL = master.bestAudioURL {
            try checkCancelled(isCancelled)
            let (audioMedia, audioPlaylistBytes) = try fetchText(audioURL, session: session)
            noteBytes(audioPlaylistBytes)
            let audioParts = parseMedia(audioMedia, base: audioURL)
            if !audioParts.segments.isEmpty || audioParts.mapURI != nil {
                let audioEst = estimateBytes(for: audioParts, bandwidth: max(96_000, master.bestBandwidth / 10))
                if audioEst > 0 {
                    let videoOnly = estimateBytes(for: videoParts, bandwidth: master.bestBandwidth)
                    tally.expectedTotal = max(tally.expectedTotal, max(videoOnly, 0) + audioEst)
                    report()
                }
                let audioIsTS = audioParts.looksLikeMPEGTS
                let out = workDir.appendingPathComponent(audioIsTS ? "audio.ts" : "audio.m4a")
                try concatTrack(
                    parts: audioParts,
                    to: out,
                    session: session,
                    onChunk: noteBytes,
                    isCancelled: isCancelled
                )
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
        } else if videoIsTS {
            // Remux MPEG-TS → MP4 so Downloads / AVPlayer treat it as a normal file.
            try remuxToMP4(input: videoFile, output: destinationURL, isCancelled: isCancelled)
        } else {
            try FileManager.default.copyItem(at: videoFile, to: destinationURL)
        }

        let size = ((try? FileManager.default.attributesOfItem(atPath: destinationURL.path))?[.size] as? NSNumber)?.int64Value ?? tally.downloaded
        XVideoOfflineProbe.log("hls.packaged", [
            "out": destinationURL.lastPathComponent,
            "size": size,
            "hadAudio": audioFile != nil
        ])
        return Result(outputURL: destinationURL, bytesWritten: size)
    }

    /// Class storage so progress closures do not inout-capture the same local `Int64`.
    private final class ByteTally {
        var downloaded: Int64 = 0
        var expectedTotal: Int64 = -1
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
        session: URLSession
    ) throws -> (String, Int64) {
        let data = try fetchData(url, session: session)
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw PackagerError.badPlaylist
        }
        return (text, Int64(data.count))
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
        onChunk: (Int64) -> Void,
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
            onChunk(Int64(data.count))
        }
    }

    // MARK: - Mux

    private static func remuxToMP4(
        input: URL,
        output: URL,
        isCancelled: () -> Bool
    ) throws {
        try checkCancelled(isCancelled)
        let asset = AVURLAsset(url: input)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough)
                ?? AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            try FileManager.default.copyItem(at: input, to: output)
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
            XVideoOfflineProbe.log("hls.remuxFail", [
                "error": export.error?.localizedDescription ?? "unknown",
                "input": input.lastPathComponent
            ])
            // Last resort: keep concatenated TS with .mp4 extension (often still playable).
            if FileManager.default.fileExists(atPath: output.path) {
                try? FileManager.default.removeItem(at: output)
            }
            try FileManager.default.copyItem(at: input, to: output)
        }
    }

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
        var totalDuration: Double
        var byteRangeTotal: Int64

        var looksLikeMPEGTS: Bool {
            if mapURI != nil { return false }
            return segments.contains { $0.lowercased().contains(".ts") }
        }
    }

    private static func estimateBytes(for media: MediaPlaylist, bandwidth: Int) -> Int64 {
        if media.byteRangeTotal > 0 { return media.byteRangeTotal }
        if media.totalDuration > 0, bandwidth > 0 {
            return Int64(media.totalDuration * Double(bandwidth) / 8.0)
        }
        if !media.segments.isEmpty, bandwidth > 0 {
            // Assume ~4s segments when EXTINF was missing.
            return Int64(Double(media.segments.count) * 4.0 * Double(bandwidth) / 8.0)
        }
        return -1
    }

    private static func parseMaster(_ text: String, base: URL) -> MasterPlaylist {
        var result = MasterPlaylist()
        var pendingBandwidth = 0
        var pendingAudioGroup: String?
        var awaitingStreamURI = false
        var sawStreamInf = false
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
                awaitingStreamURI = true
                sawStreamInf = true
                continue
            }
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            // Only URI lines that immediately follow STREAM-INF are variants.
            // Media playlists list hundreds of `.ts` segment URIs — never treat those as variants
            // (previously the last segment won and fetch returned HTTP 400).
            guard awaitingStreamURI else { continue }
            awaitingStreamURI = false
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

        // Already a media playlist (no STREAM-INF) — download its own segments.
        if !sawStreamInf, text.contains("#EXTINF") || text.contains("#EXT-X-MAP") {
            result.bestVideoURL = base
            result.bestBandwidth = 0
        }
        return result
    }

    private static func parseMedia(_ text: String, base: URL) -> MediaPlaylist {
        var mapURI: String?
        var segments: [String] = []
        var totalDuration: Double = 0
        var byteRangeTotal: Int64 = 0
        let lines = text.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }
        for line in lines {
            if line.hasPrefix("#EXT-X-MAP:") {
                let attrs = parseAttrs(String(line.dropFirst("#EXT-X-MAP:".count)))
                mapURI = attrs["URI"]
                if let br = attrs["BYTERANGE"], let len = byteRangeLength(br) {
                    byteRangeTotal += len
                }
                continue
            }
            if line.hasPrefix("#EXTINF:") {
                let raw = String(line.dropFirst("#EXTINF:".count))
                let value = raw.split(separator: ",", maxSplits: 1).first
                    .map(String.init)?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                if let seconds = Double(value) { totalDuration += seconds }
                continue
            }
            if line.hasPrefix("#EXT-X-BYTERANGE:") {
                let raw = String(line.dropFirst("#EXT-X-BYTERANGE:".count))
                    .trimmingCharacters(in: .whitespaces)
                if let len = byteRangeLength(raw) { byteRangeTotal += len }
                continue
            }
            if line.isEmpty || line.hasPrefix("#") { continue }
            segments.append(line)
        }
        return MediaPlaylist(
            baseURL: base,
            mapURI: mapURI,
            segments: segments,
            totalDuration: totalDuration,
            byteRangeTotal: byteRangeTotal
        )
    }

    /// `#EXT-X-BYTERANGE:length[@offset]` → length.
    private static func byteRangeLength(_ raw: String) -> Int64? {
        let lengthPart = raw.split(separator: "@", maxSplits: 1).first.map(String.init) ?? raw
        return Int64(lengthPart.trimmingCharacters(in: .whitespaces))
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
