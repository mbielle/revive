import SwiftUI

/// Standard first screen of a module: illustration on the left, title, subtitle and
/// feature list on the right, main action button at the bottom.
struct ModuleLanding<Accessory: View, Action: View>: View {
    let module: AppModule
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var action: Action

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            HStack(spacing: 40) {
                HeroIllustration(style: module.hero, symbol: module.symbol, theme: module.theme, size: 340)
                    .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 18) {
                    Text(module.headline).screenTitle()
                    Text(module.subtitle).screenSubtitle()
                        .frame(maxWidth: 440, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(module.features) { feature in
                            HStack(spacing: 16) {
                                FeatureBadge(symbol: feature.symbol, theme: module.theme)
                                Text(feature.title)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .padding(.top, 22)
                    accessory.padding(.top, 10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 40)
            Spacer(minLength: 20)
            action
                .padding(.bottom, 34)
        }
    }
}

extension ModuleLanding where Accessory == EmptyView {
    init(module: AppModule, @ViewBuilder action: () -> Action) {
        self.module = module
        self.accessory = EmptyView()
        self.action = action()
    }
}

/// Screen shown while a scan or a cleanup is running.
struct WorkingView: View {
    let module: AppModule
    let title: LocalizedStringResource
    let progress: Double?
    let detail: String
    var stat: String?
    let onStop: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            HStack(spacing: 50) {
                ZStack {
                    ProgressRing(fraction: progress, theme: module.theme, lineWidth: 7)
                        .frame(width: 360, height: 360)
                    HeroIllustration(style: module.hero, symbol: module.symbol, theme: module.theme, size: 270)
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 14) {
                    Text(title).screenTitle()
                    if let stat {
                        Text(stat)
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                    }
                    Text(detail)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 420, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 40)
            Spacer(minLength: 20)
            Group {
                if let onStop {
                    ScanButton(title: "Stop", theme: module.theme, pulses: false, action: onStop)
                } else {
                    Color.clear.frame(width: 104, height: 104)
                }
            }
            .padding(.bottom, 34)
        }
    }
}
