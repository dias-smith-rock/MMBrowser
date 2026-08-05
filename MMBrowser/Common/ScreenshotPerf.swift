import Foundation
import UIKit

/// Lightweight timing / counter logs for screenshot open + editor interaction.
/// Filter Xcode console with: `[ShotPerf]`
enum ScreenshotPerf {
    #if DEBUG
    static let enabled = true
    #else
    static let enabled = false
    #endif
    private static let tag = "[ShotPerf]"

    private static var sessionStart: CFAbsoluteTime?
    private static var refreshCount = 0
    private static var layoutCount = 0
    private static var panRefreshCount = 0
    private static var lastPanLog: CFAbsoluteTime = 0

    static func beginSession(_ reason: String) {
        guard enabled else { return }
        sessionStart = CFAbsoluteTimeGetCurrent()
        refreshCount = 0
        layoutCount = 0
        panRefreshCount = 0
        log("SESSION begin — \(reason)")
    }

    static func mark(_ event: String, since start: CFAbsoluteTime? = nil, extra: String = "") {
        guard enabled else { return }
        var parts = [event]
        if let start = start {
            parts.append(String(format: "%.1fms", (CFAbsoluteTimeGetCurrent() - start) * 1000))
        }
        if let sessionStart = sessionStart {
            parts.append(String(format: "t+%.1fms", (CFAbsoluteTimeGetCurrent() - sessionStart) * 1000))
        }
        if !extra.isEmpty { parts.append(extra) }
        log(parts.joined(separator: " | "))
    }

    static func measure<T>(_ event: String, _ body: () -> T) -> T {
        guard enabled else { return body() }
        let start = CFAbsoluteTimeGetCurrent()
        let value = body()
        mark(event, since: start)
        return value
    }

    static func now() -> CFAbsoluteTime { CFAbsoluteTimeGetCurrent() }

    static func noteLayout() {
        guard enabled else { return }
        layoutCount += 1
        mark("editor.layout", extra: "count=\(layoutCount)")
    }

    static func noteRefresh(source: String, durationMs: Double, breakdown: String = "") {
        guard enabled else { return }
        refreshCount += 1
        var extra = "src=\(source) count=\(refreshCount)"
        if !breakdown.isEmpty { extra += " \(breakdown)" }
        if durationMs >= 8 {
            log(String(format: "editor.refresh SLOW %.1fms | %@", durationMs, extra))
        } else if refreshCount <= 5 || refreshCount % 10 == 0 {
            log(String(format: "editor.refresh %.1fms | %@", durationMs, extra))
        }
    }

    static func notePanRefresh(durationMs: Double) {
        guard enabled else { return }
        panRefreshCount += 1
        let t = CFAbsoluteTimeGetCurrent()
        // Log first few, then at most ~5/sec when slow, or every 15th sample.
        let shouldLog = panRefreshCount <= 3
            || durationMs >= 8
            || panRefreshCount % 15 == 0
            || (t - lastPanLog) > 0.2
        guard shouldLog else { return }
        lastPanLog = t
        log(String(format: "editor.panRefresh %.1fms | n=%d", durationMs, panRefreshCount))
    }

    static func endSessionSummary() {
        guard enabled else { return }
        mark(
            "SESSION summary",
            extra: "layouts=\(layoutCount) refreshes=\(refreshCount) panRefreshes=\(panRefreshCount)"
        )
    }

    private static func log(_ message: String) {
        print("\(tag) \(message)")
    }
}
