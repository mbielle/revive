import CoreGraphics

/// Packs circles whose areas are proportional to sizes, biggest in the middle.
///
/// Greedy placement: each new circle is put tangent to an already placed one, at the
/// free position closest to the center. Good enough for the few dozen bubbles Space Lens shows.
enum BubbleLayout {
    struct Bubble {
        let index: Int
        var center: CGPoint
        var radius: CGFloat
    }

    static func layout(sizes: [Int64], in bounds: CGSize, gap: CGFloat = 6) -> [Bubble] {
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
}
