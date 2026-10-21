import SwiftUI

/// Silhouette of a module's illustration.
enum HeroStyle {
    case monitor, disc, octagon, chevron, squircle, folder, lens, cloud
}

/// The big glossy object of each landing screen: an extruded slab in the module's colors
/// carrying a white embossed symbol, floating gently. Entirely drawn in SwiftUI (no bitmap).
struct HeroIllustration: View {
    let style: HeroStyle
    let symbol: String
    let theme: ModuleTheme
    var size: CGFloat = 360
    var animated = true

    @State private var floating = false

    var body: some View {
        ZStack {
            Ellipse()
                .fill(.black.opacity(0.35))
                .frame(width: size * 0.72, height: size * 0.09)
                .blur(radius: 18)
                .offset(y: size * 0.47)
                .scaleEffect(floating ? 0.92 : 1)

            Group {
                switch style {
                case .monitor: monitor
                default: slab
                }
            }
            .offset(y: floating ? -size * 0.02 : size * 0.02)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard animated else { return }
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) { floating = true }
        }
    }

    // MARK: - Slab

    private var depth: Int { Int(size * 0.055) }

    private var slab: some View {
        let shape = style.shape
        let frame = style.frame(size)
        return ZStack {
            // Extrusion: stacked copies give the object its thickness.
            ForEach((1...depth).reversed(), id: \.self) { layer in
                shape
                    .fill(theme.dark.blend(theme.button, Double(depth - layer) / Double(depth) * 0.5))
                    .offset(y: CGFloat(layer))
            }
            shape.fill(
                LinearGradient(colors: [theme.glow.blend(.white, 0.35), theme.button, theme.button.blend(theme.dark, 0.35)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            // Glassy reflection on the upper half.
            shape
                .fill(LinearGradient(colors: [.white.opacity(0.42), .white.opacity(0)], startPoint: .top, endPoint: .center))
                .blendMode(.screen)
            // Bright bevel along the rim.
            if style != .cloud {
                shape.stroke(
                    LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.1), theme.glow.opacity(0.6)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: max(2, size * 0.008)
                )
            }
            EmbossedSymbol(name: style == .lens ? "magnifyingglass" : symbol, theme: theme, size: size * 0.34)
                .offset(y: style == .folder ? size * 0.04 : 0)
        }
        .frame(width: frame.width, height: frame.height)
        .rotation3DEffect(.degrees(12), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
        .shadow(color: theme.dark.opacity(0.55), radius: size * 0.08, y: size * 0.06)
    }

    // MARK: - Monitor (Smart Care)

    private var monitor: some View {
        let screen = RoundedRectangle(cornerRadius: size * 0.07, style: .continuous)
        return VStack(spacing: 0) {
            ZStack {
                ForEach((1...depth).reversed(), id: \.self) { layer in
                    screen.fill(theme.dark.blend(theme.button, 0.3)).offset(y: CGFloat(layer))
                }
                screen.fill(
                    LinearGradient(colors: [theme.glow.blend(.white, 0.3), theme.button, theme.glow],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                screen
                    .fill(LinearGradient(colors: [.white.opacity(0.4), .clear], startPoint: .top, endPoint: .center))
                    .blendMode(.screen)
                screen.stroke(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.1)], startPoint: .top, endPoint: .bottom),
                              lineWidth: max(2, size * 0.008))
                EmbossedSymbol(name: "sparkles", theme: theme, size: size * 0.3)
            }
            .frame(width: size * 0.9, height: size * 0.58)
            .rotation3DEffect(.degrees(10), axis: (x: 1, y: 0, z: 0), perspective: 0.6)

            // Stand.
            LinearGradient(colors: [Color(white: 0.92), Color(white: 0.7)], startPoint: .leading, endPoint: .trailing)
                .frame(width: size * 0.3, height: size * 0.16)
                .overlay(alignment: .top) { Color.black.opacity(0.18).frame(height: size * 0.02).blur(radius: 3) }
            Capsule()
                .fill(LinearGradient(colors: [Color(white: 0.98), Color(white: 0.72)], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.5, height: size * 0.035)
        }
        .shadow(color: theme.dark.opacity(0.55), radius: size * 0.08, y: size * 0.06)
    }
}

/// A white symbol with a few pixels of depth, like a glossy plastic glyph.
struct EmbossedSymbol: View {
    let name: String
    let theme: ModuleTheme
    let size: CGFloat

    var body: some View {
        let glyph = Image(systemName: name).font(.system(size: size, weight: .bold))
        ZStack {
            ForEach((1...5).reversed(), id: \.self) { layer in
                glyph.foregroundStyle(Color(white: 0.78).blend(theme.button, 0.15)).offset(y: CGFloat(layer) * size / 70)
            }
            glyph.foregroundStyle(LinearGradient(colors: [.white, Color(white: 0.93).blend(theme.glow, 0.12)],
                                                 startPoint: .top, endPoint: .bottom))
        }
        .shadow(color: theme.dark.opacity(0.5), radius: size * 0.08, y: size * 0.06)
    }
}

// MARK: - Shapes

extension HeroStyle {
    var shape: AnyShape {
        switch self {
        case .disc, .lens: AnyShape(Circle())
        case .octagon: AnyShape(RoundedPolygon(sides: 8, cornerFraction: 0.18, rotation: .degrees(22.5)))
        case .squircle, .monitor: AnyShape(RoundedRectangle(cornerRadius: 70, style: .continuous))
        case .chevron: AnyShape(ChevronShape())
        case .folder: AnyShape(FolderShape())
        case .cloud: AnyShape(CloudShape())
        }
    }

    func frame(_ size: CGFloat) -> CGSize {
        switch self {
        case .disc, .lens: CGSize(width: size * 0.82, height: size * 0.82)
        case .octagon: CGSize(width: size * 0.86, height: size * 0.86)
        case .squircle, .monitor: CGSize(width: size * 0.78, height: size * 0.78)
        case .chevron: CGSize(width: size * 0.9, height: size * 0.82)
        case .folder: CGSize(width: size * 0.92, height: size * 0.72)
        case .cloud: CGSize(width: size * 0.96, height: size * 0.64)
        }
    }
}

/// Regular polygon with rounded corners.
struct RoundedPolygon: Shape {
    let sides: Int
    /// Corner radius as a fraction of the shape's radius.
    var cornerFraction: CGFloat = 0.15
    var rotation: Angle = .zero

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let points = (0..<sides).map { i -> CGPoint in
            let angle = Double(i) / Double(sides) * 2 * .pi - .pi / 2 + rotation.radians
            return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        }
        return Path.rounded(points: points, cornerRadius: radius * cornerFraction)
    }
}

/// Wide badge with a notch at the bottom, used for Performance.
struct ChevronShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, x = rect.minX, y = rect.minY
        let points = [
            CGPoint(x: x, y: y + h * 0.22),
            CGPoint(x: x + w * 0.5, y: y),
            CGPoint(x: x + w, y: y + h * 0.22),
            CGPoint(x: x + w, y: y + h),
            CGPoint(x: x + w * 0.5, y: y + h * 0.78),
            CGPoint(x: x, y: y + h),
        ]
        return Path.rounded(points: points, cornerRadius: min(w, h) * 0.1)
    }
}

struct FolderShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, x = rect.minX, y = rect.minY
        let points = [
            CGPoint(x: x, y: y),
            CGPoint(x: x + w * 0.38, y: y),
            CGPoint(x: x + w * 0.46, y: y + h * 0.13),
            CGPoint(x: x + w, y: y + h * 0.13),
            CGPoint(x: x + w, y: y + h),
            CGPoint(x: x, y: y + h),
        ]
        return Path.rounded(points: points, cornerRadius: min(w, h) * 0.08)
    }
}

struct CloudShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, x = rect.minX, y = rect.minY
        var path = Path()
        path.addRoundedRect(in: CGRect(x: x, y: y + h * 0.45, width: w, height: h * 0.55), cornerSize: CGSize(width: h * 0.27, height: h * 0.27))
        path.addEllipse(in: CGRect(x: x + w * 0.12, y: y + h * 0.25, width: w * 0.38, height: h * 0.6))
        path.addEllipse(in: CGRect(x: x + w * 0.32, y: y, width: w * 0.46, height: h * 0.78))
        path.addEllipse(in: CGRect(x: x + w * 0.6, y: y + h * 0.3, width: w * 0.3, height: h * 0.5))
        return path
    }
}

extension Path {
    /// Closed polygon through `points` with every corner rounded.
    static func rounded(points: [CGPoint], cornerRadius: CGFloat) -> Path {
        var path = Path()
        guard points.count > 2 else { return path }
        let n = points.count
        let start = CGPoint(x: (points[n - 1].x + points[0].x) / 2, y: (points[n - 1].y + points[0].y) / 2)
        path.move(to: start)
        for i in 0..<n {
            path.addArc(tangent1End: points[i], tangent2End: points[(i + 1) % n], radius: cornerRadius)
        }
        path.closeSubpath()
        return path
    }
}
