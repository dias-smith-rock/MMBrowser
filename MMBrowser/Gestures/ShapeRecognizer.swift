import CoreGraphics
import Foundation

enum ShapeRecognizer {
    private static let minPoints = 8
    private static let minPathLength: CGFloat = 60

    static func recognize(_ points: [CGPoint]) -> GestureShape? {
        let simplified = simplify(points, minDistance: 4)
        guard simplified.count >= minPoints else { return nil }
        let length = pathLength(simplified)
        guard length >= minPathLength else { return nil }

        let box = boundingBox(simplified)
        let diag = hypot(box.width, box.height)
        guard diag > 20 else { return nil }

        let startEnd = hypot(simplified.last!.x - simplified.first!.x, simplified.last!.y - simplified.first!.y)
        let closure = startEnd / max(diag, 1)
        let corners = detectCorners(simplified)
        let reversals = directionReversals(simplified)

        // Circle: roughly closed, path length near ellipse perimeter, few sharp corners.
        let perimeter = .pi * (1.5 * (box.width + box.height) - sqrt(box.width * box.height))
        let circleScore = closure < 0.35
            && abs(length / max(perimeter, 1) - 1) < 0.55
            && corners.count <= 2
            && box.width / max(box.height, 1) > 0.45
            && box.width / max(box.height, 1) < 2.2

        if circleScore { return .circle }

        // Zigzag: many direction changes, not closed.
        if reversals >= 3 && closure > 0.25 { return .zigzag }

        // Checkmark: typically 1 sharp corner; second leg shorter; overall down-right then up-right.
        if let check = matchCheckmark(simplified, corners: corners) { return check }

        // Triangle: 2–3 corners and somewhat closed.
        if corners.count >= 2 && corners.count <= 4 && closure < 0.45 {
            return .triangle
        }

        // Single V / Λ
        if corners.count == 1 {
            let c = corners[0]
            let midY = simplified[c].y
            let avgEndY = (simplified.first!.y + simplified.last!.y) / 2
            if midY > avgEndY + diag * 0.12 { return .vDown }
            if midY < avgEndY - diag * 0.12 { return .vUp }
        }

        // Soft zigzag fallback
        if reversals >= 2 && closure > 0.3 { return .zigzag }

        return nil
    }

    // MARK: - Geometry helpers

    private static func simplify(_ points: [CGPoint], minDistance: CGFloat) -> [CGPoint] {
        guard var last = points.first else { return [] }
        var result = [last]
        for p in points.dropFirst() {
            if hypot(p.x - last.x, p.y - last.y) >= minDistance {
                result.append(p)
                last = p
            }
        }
        if let end = points.last, end != result.last {
            result.append(end)
        }
        return result
    }

    private static func pathLength(_ points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    private static func boundingBox(_ points: [CGPoint]) -> CGRect {
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        for p in points {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: max(maxX - minX, 1), height: max(maxY - minY, 1))
    }

    private static func detectCorners(_ points: [CGPoint]) -> [Int] {
        guard points.count >= 5 else { return [] }
        var corners: [Int] = []
        let window = 2
        for i in window..<(points.count - window) {
            let a = points[i - window]
            let b = points[i]
            let c = points[i + window]
            let v1 = CGPoint(x: b.x - a.x, y: b.y - a.y)
            let v2 = CGPoint(x: c.x - b.x, y: c.y - b.y)
            let len1 = hypot(v1.x, v1.y)
            let len2 = hypot(v2.x, v2.y)
            guard len1 > 1, len2 > 1 else { continue }
            let cosAngle = (v1.x * v2.x + v1.y * v2.y) / (len1 * len2)
            let clamped = max(-1, min(1, cosAngle))
            let angle = acos(clamped) * 180 / .pi
            // Sharp turn
            if angle > 45 && angle < 160 {
                if let last = corners.last, i - last < 4 { continue }
                corners.append(i)
            }
        }
        return corners
    }

    private static func directionReversals(_ points: [CGPoint]) -> Int {
        guard points.count >= 6 else { return 0 }
        var dirs: [CGFloat] = []
        let step = max(1, points.count / 20)
        var i = 0
        while i + step < points.count {
            let a = points[i]
            let b = points[i + step]
            dirs.append(atan2(b.y - a.y, b.x - a.x))
            i += step
        }
        var count = 0
        for j in 1..<dirs.count {
            var delta = abs(dirs[j] - dirs[j - 1])
            if delta > .pi { delta = 2 * .pi - delta }
            if delta > (.pi * 0.55) { count += 1 }
        }
        return count
    }

    private static func matchCheckmark(_ points: [CGPoint], corners: [Int]) -> GestureShape? {
        guard let cornerIndex = corners.first ?? sharpestIndex(points) else { return nil }
        let start = points.first!
        let corner = points[cornerIndex]
        let end = points.last!
        let leg1 = hypot(corner.x - start.x, corner.y - start.y)
        let leg2 = hypot(end.x - corner.x, end.y - corner.y)
        guard leg1 > 20, leg2 > 12, leg2 < leg1 * 1.15 else { return nil }

        // Classic check: first stroke goes down-right, second goes up-right.
        let downRight = (corner.x > start.x - 10) && (corner.y > start.y + 8)
        let upRight = (end.x > corner.x + 8) && (end.y < corner.y - 8)
        if downRight && upRight { return .checkmark }

        // Mirrored / loose check: overall rightward with one bend.
        let overallRight = end.x > start.x + 20
        let hasBend = corners.count <= 2
        if overallRight && hasBend && leg2 < leg1 * 0.95 { return .checkmark }
        return nil
    }

    private static func sharpestIndex(_ points: [CGPoint]) -> Int? {
        guard points.count >= 5 else { return nil }
        var best: (Int, CGFloat)?
        for i in 2..<(points.count - 2) {
            let a = points[i - 2], b = points[i], c = points[i + 2]
            let v1 = CGPoint(x: b.x - a.x, y: b.y - a.y)
            let v2 = CGPoint(x: c.x - b.x, y: c.y - b.y)
            let len1 = hypot(v1.x, v1.y), len2 = hypot(v2.x, v2.y)
            guard len1 > 1, len2 > 1 else { continue }
            let cosAngle = max(-1, min(1, (v1.x * v2.x + v1.y * v2.y) / (len1 * len2)))
            let angle = acos(cosAngle)
            if best == nil || angle > best!.1 {
                best = (i, angle)
            }
        }
        guard let best, best.1 > (.pi * 0.35) else { return nil }
        return best.0
    }
}
