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

        // Circle ○ — closed loop only (not confused with a swipe).
        let perimeter = .pi * (1.5 * (box.width + box.height) - sqrt(box.width * box.height))
        let circleScore = closure < 0.35
            && abs(length / max(perimeter, 1) - 1) < 0.55
            && corners.count <= 2
            && box.width / max(box.height, 1) > 0.45
            && box.width / max(box.height, 1) < 2.2

        if circleScore { return .circle }

        // Hook → / Hook ← — short reverse bend + long horizontal stroke.
        // A plain swipe has no corner and will not match.
        if let hook = matchHorizontalHook(simplified, corners: corners, closure: closure) {
            return hook
        }

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
            if angle > 45 && angle < 160 {
                if let last = corners.last, i - last < 4 { continue }
                corners.append(i)
            }
        }
        return corners
    }

    private static func matchHorizontalHook(
        _ points: [CGPoint],
        corners: [Int],
        closure: CGFloat
    ) -> GestureShape? {
        guard closure > 0.15 else { return nil }
        guard corners.count <= 2 else { return nil }

        let cornerIndex = primaryCornerIndex(points, corners: corners) ?? sharpestIndex(points)
        guard let cornerIndex else { return nil }

        let start = points.first!
        let corner = points[cornerIndex]
        let end = points.last!
        let d1 = CGPoint(x: corner.x - start.x, y: corner.y - start.y)
        let d2 = CGPoint(x: end.x - corner.x, y: end.y - corner.y)
        let leg1 = hypot(d1.x, d1.y)
        let leg2 = hypot(d2.x, d2.y)

        guard leg1 > 16, leg2 > 48, leg2 > leg1 * 1.35 else { return nil }
        // Main stroke must be clearly horizontal.
        guard abs(d2.x) > abs(d2.y) * 1.5, abs(d2.x) > 40 else { return nil }

        if d2.x > 0, d1.x < -10 { return .hookRight }
        if d2.x < 0, d1.x > 10 { return .hookLeft }
        return nil
    }

    private static func primaryCornerIndex(_ points: [CGPoint], corners: [Int]) -> Int? {
        guard !corners.isEmpty else { return nil }
        var best: (Int, CGFloat)?
        for i in corners {
            guard i > 1, i + 1 < points.count - 1 else { continue }
            let a = points[max(0, i - 2)]
            let b = points[i]
            let c = points[min(points.count - 1, i + 2)]
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
        return best?.0 ?? corners.first
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
