import CoreGraphics

/// Packs circles whose areas are proportional to sizes, biggest in the middle.
///
/// Greedy placement: each new circle is put tangent to an already placed one, at the
/// free position closest to the center. Good enough for the few dozen bubbles Storage Map shows.
public enum BubbleLayout {
    public struct Bubble: Sendable {
        public let index: Int
        public var center: CGPoint
        public var radius: CGFloat
    }

    public static func layout(sizes: [Int64], in bounds: CGSize, gap: CGFloat = 6) -> [Bubble] {
        guard let maxSize = sizes.max(), maxSize > 0, bounds.width > 0, bounds.height > 0 else { return [] }
        // Radius ∝ √size so areas compare like sizes; very small items keep a visible minimum.
        let radii = sizes.map { max(0.12, sqrt(Double($0) / Double(maxSize))) * 100 }
        var placed: [Bubble] = []

        for (index, r) in radii.enumerated() {
            let radius = CGFloat(r)
            if placed.isEmpty {
                placed.append(Bubble(index: index, center: .zero, radius: radius))
                continue
            }
            var best: CGPoint?
            var bestDistance = CGFloat.infinity
            for other in placed {
                for step in 0..<48 {
                    let angle = Double(step) / 48 * 2 * .pi
                    let distance = other.radius + radius + gap
                    let candidate = CGPoint(x: other.center.x + cos(angle) * distance * 1.25,
                                            y: other.center.y + sin(angle) * distance)
                    let fromCenter = hypot(candidate.x / 1.25, candidate.y)
                    guard fromCenter < bestDistance else { continue }
                    let overlaps = placed.contains { hypot($0.center.x - candidate.x, $0.center.y - candidate.y) < $0.radius + radius + gap - 0.5 }
                    if !overlaps {
                        best = candidate
                        bestDistance = fromCenter
                    }
                }
            }
            placed.append(Bubble(index: index, center: best ?? .zero, radius: radius))
        }

        // Scale and center the cluster in the available bounds.
        let minX = placed.map { $0.center.x - $0.radius }.min() ?? 0
        let maxX = placed.map { $0.center.x + $0.radius }.max() ?? 0
        let minY = placed.map { $0.center.y - $0.radius }.min() ?? 0
        let maxY = placed.map { $0.center.y + $0.radius }.max() ?? 0
        let scale = min(bounds.width / (maxX - minX), bounds.height / (maxY - minY))
        let offset = CGPoint(x: bounds.width / 2 - (minX + maxX) / 2 * scale, y: bounds.height / 2 - (minY + maxY) / 2 * scale)
        return placed.map {
            Bubble(index: $0.index,
                   center: CGPoint(x: $0.center.x * scale + offset.x, y: $0.center.y * scale + offset.y),
                   radius: $0.radius * scale)
        }
    }

    /// Radius of a hovered bubble: big enough to show its name, at most a little larger than its neighbors expect.
    public static func hoveredRadius(for radius: CGFloat) -> CGFloat {
        min(max(radius * 1.3, 60), radius * 3)
    }

    /// Grows bubble `hovered` and pushes the others away so nothing overlaps, staying inside `bounds`.
    public static func spread(_ bubbles: [Bubble], hovered: Int?, in bounds: CGSize, gap: CGFloat = 6) -> [Bubble] {
        guard let hovered, let pinned = bubbles.firstIndex(where: { $0.index == hovered }) else { return bubbles }
        var result = bubbles
        result[pinned].radius = hoveredRadius(for: bubbles[pinned].radius)
        result[pinned].center = clamped(result[pinned], in: bounds)

        for _ in 0..<60 {
            var moved = false
            for i in result.indices {
                for j in result.indices where j > i {
                    let dx = result[j].center.x - result[i].center.x
                    let dy = result[j].center.y - result[i].center.y
                    let distance = max(hypot(dx, dy), 0.01)
                    let overlap = result[i].radius + result[j].radius + gap - distance
                    guard overlap > 0.5 else { continue }
                    moved = true
                    let (ux, uy) = (dx / distance, dy / distance)
                    // The hovered bubble stays put; others share the push.
                    let shareI: CGFloat = i == pinned ? 0 : (j == pinned ? 1 : 0.5)
                    let shareJ = 1 - shareI
                    result[i].center.x -= ux * overlap * shareI
                    result[i].center.y -= uy * overlap * shareI
                    result[j].center.x += ux * overlap * shareJ
                    result[j].center.y += uy * overlap * shareJ
                }
            }
            for k in result.indices where k != pinned { result[k].center = clamped(result[k], in: bounds) }
            if !moved { break }
        }
        return result
    }

    private static func clamped(_ bubble: Bubble, in bounds: CGSize) -> CGPoint {
        let r = min(bubble.radius, bounds.width / 2, bounds.height / 2)
        return CGPoint(x: min(max(bubble.center.x, r), bounds.width - r),
                       y: min(max(bubble.center.y, r), bounds.height - r))
    }

    /// Index of the bubble under `point`, preferring `current` so a growing bubble keeps the hover.
    public static func bubble(at point: CGPoint, in bubbles: [Bubble], current: Int?) -> Int? {
        func contains(_ b: Bubble) -> Bool { hypot(point.x - b.center.x, point.y - b.center.y) <= b.radius }
        if let current, let b = bubbles.first(where: { $0.index == current }), contains(b) { return current }
        return bubbles.first(where: contains)?.index
    }
}
