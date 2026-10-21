import SwiftUI

/// The color set of one module: every screen of the module is painted from these four colors.
struct ModuleTheme: Equatable {
    /// Upper-left of the background gradient.
    let light: Color
    /// Lower-right of the background gradient.
    let dark: Color
    /// Halo behind the illustration and the main button.
    let glow: Color
    /// Fill of the main circular button and of feature badges.
    let button: Color

    init(light: UInt32, dark: UInt32, glow: UInt32, button: UInt32) {
        self.light = Color(hex: light)
        self.dark = Color(hex: dark)
        self.glow = Color(hex: glow)
        self.button = Color(hex: button)
    }

    var badgeGradient: LinearGradient {
        LinearGradient(colors: [glow.blend(.white, 0.25), button], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// Linear blend in sRGB; available on every supported macOS, unlike `Color.mix(with:by:in:)`.
    func blend(_ other: Color, _ amount: Double) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let b = NSColor(other).usingColorSpace(.sRGB) ?? .black
        let t = min(max(amount, 0), 1)
        return Color(
            .sRGB,
            red: a.redComponent + (b.redComponent - a.redComponent) * t,
            green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
            blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t,
            opacity: a.alphaComponent + (b.alphaComponent - a.alphaComponent) * t
        )
    }
}

/// Full-window painted background of a module.
struct ModuleBackground: View {
    let theme: ModuleTheme

    var body: some View {
        ZStack {
            LinearGradient(colors: [theme.light, theme.dark], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [theme.glow.opacity(0.32), .clear], center: UnitPoint(x: 0.42, y: 0.42), startRadius: 10, endRadius: 520)
                .blendMode(.screen)
            LinearGradient(colors: [.clear, .black.opacity(0.28)], startPoint: .center, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }
}
