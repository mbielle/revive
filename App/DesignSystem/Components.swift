import SwiftUI

/// The large glowing circular button at the bottom of every module ("Scan", "Clean", "Stop"...).
struct ScanButton: View {
    let title: LocalizedStringResource
    let theme: ModuleTheme
    var diameter: CGFloat = 104
    var pulses = true
    let action: () -> Void

    @State private var pulse = false
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if pulses {
                    Circle()
                        .stroke(theme.glow.opacity(0.7), lineWidth: 2)
                        .scaleEffect(pulse ? 1.45 : 1)
                        .opacity(pulse ? 0 : 0.8)
                }
                Circle()
                    .fill(RadialGradient(colors: [theme.glow.blend(.white, 0.15), theme.button],
                                         center: .init(x: 0.5, y: 0.25), startRadius: 2, endRadius: diameter * 0.7))
                Circle()
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.35)], startPoint: .top, endPoint: .bottom),
                                  lineWidth: 2.5)
                Text(title)
                    .font(.system(size: diameter * 0.22, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: diameter * 0.78)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            }
            .frame(width: diameter, height: diameter)
            .shadow(color: theme.glow.opacity(hovering ? 0.95 : 0.7), radius: hovering ? 34 : 26)
            .scaleEffect(hovering ? 1.04 : 1)
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.3), value: hovering)
        .onAppear {
            guard pulses else { return }
            withAnimation(.easeOut(duration: 2).repeatForever(autoreverses: false)) { pulse = true }
        }
        .keyboardShortcut(.defaultAction)
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// A rounded translucent pill button used for secondary actions.
struct PillButton: View {
    let title: LocalizedStringResource
    var symbol: String?
    var prominent = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(prominent ? Color.black.opacity(0.85) : .white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                Capsule().fill(prominent ? AnyShapeStyle(Color(hex: 0xFFD43B)) : AnyShapeStyle(.white.opacity(hovering ? 0.24 : 0.15)))
            }
            .overlay { Capsule().strokeBorder(.white.opacity(prominent ? 0 : 0.18)) }
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
    }
}

/// Rounded square with the module gradient and a white symbol, used in feature lists and cards.
struct FeatureBadge: View {
    let symbol: String
    let theme: ModuleTheme
    var size: CGFloat = 36

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(theme.badgeGradient)
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom))
            }
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
            }
            .frame(width: size, height: size)
            .shadow(color: theme.dark.opacity(0.4), radius: 6, y: 3)
    }
}

/// Translucent card. Uses Liquid Glass on macOS 26 and later.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 22
    var padding: CGFloat = 20
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(cornerRadius: cornerRadius)
    }
}

extension View {
    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat = 22) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26, *) {
            self
                .background(shape.fill(.white.opacity(0.06)))
                .glassEffect(.clear, in: shape)
        } else {
            self
                .background(shape.fill(.white.opacity(0.1)))
                .overlay(shape.strokeBorder(.white.opacity(0.16)))
        }
    }

    /// Big light title used at the top of every screen.
    func screenTitle() -> some View {
        font(.system(size: 46, weight: .regular)).foregroundStyle(.white).tracking(-0.5)
    }

    func screenSubtitle() -> some View {
        font(.system(size: 18)).foregroundStyle(.white.opacity(0.72)).lineSpacing(3)
    }
}

/// Circular progress ring with a soft glow.
struct ProgressRing: View {
    /// nil shows an indeterminate spinning arc.
    let fraction: Double?
    let theme: ModuleTheme
    var lineWidth: CGFloat = 8

    @State private var spin = false

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction.map { max(0.02, $0) } ?? 0.25)
                .stroke(LinearGradient(colors: [.white, theme.glow], startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .rotationEffect(.degrees(fraction == nil && spin ? 360 : 0))
                .shadow(color: theme.glow, radius: 8)
                .animation(.easeOut(duration: 0.3), value: fraction)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { spin = true }
        }
    }
}

/// Checkbox styled for dark gradients.
struct CheckBox: View {
    enum State { case on, off, mixed }
    let state: State
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(state == .off ? AnyShapeStyle(.white.opacity(0.08)) : AnyShapeStyle(.white))
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.white.opacity(state == .off ? 0.5 : 0))
                }
                .overlay {
                    if state != .off {
                        Image(systemName: state == .on ? "checkmark" : "minus")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.black.opacity(0.75))
                    }
                }
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Size text shown everywhere ("4.2 GB").
func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
