import LucentKit
import SwiftUI

struct SmartCareView: View {
    let model: SmartCareModel
    private let module = AppModule.smartCare

    var body: some View {
        Group {
            switch model.phase {
            case .idle:
                ModuleLanding(module: module) {
                    ScanButton(title: "Scan", theme: module.theme) { model.scan() }
                }
            case .scanning:
                SmartCareScanningView(model: model)
            case .results:
                if let category = model.cleanup.reviewing {
                    CleanupReviewView(model: model.cleanup, category: category)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    SmartCareResultsView(model: model)
                }
            case .running:
                WorkingView(module: module, title: "Taking care of your Mac…", progress: model.cleanup.progress.fraction,
                            detail: model.cleanup.progress.currentPath, stat: formatBytes(model.cleanup.progress.bytesFound), onStop: nil)
            case .done:
                if let report = model.cleanup.report {
                    CompletionView(module: module, report: report) { model.reset() }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.phase)
        .animation(.easeInOut(duration: 0.3), value: model.cleanup.reviewing)
    }
}

private struct SmartCareScanningView: View {
    let model: SmartCareModel
    private let module = AppModule.smartCare

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            HStack(spacing: 50) {
                ZStack {
                    ProgressRing(fraction: overallProgress, theme: module.theme, lineWidth: 7)
                        .frame(width: 360, height: 360)
                    HeroIllustration(style: module.hero, symbol: module.symbol, theme: module.theme, size: 260)
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 22) {
                    Text("Scanning your Mac…").screenTitle()
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(SmartCareModel.Step.allCases) { step in
                            HStack(spacing: 14) {
                                ZStack {
                                    if step.rawValue < model.currentStep.rawValue {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.white)
                                    } else if step == model.currentStep {
                                        ProgressView().controlSize(.small).tint(.white)
                                    } else {
                                        Image(systemName: "circle").foregroundStyle(.white.opacity(0.4))
                                    }
                                }
                                .font(.system(size: 20))
                                .frame(width: 24)
                                Text(step.title)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.white.opacity(step.rawValue <= model.currentStep.rawValue ? 1 : 0.5))
                            }
                        }
                    }
                    Text(model.cleanup.progress.currentPath)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 420, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 40)
            Spacer(minLength: 20)
            ScanButton(title: "Stop", theme: module.theme, pulses: false) { model.stop() }
                .padding(.bottom, 34)
        }
    }

    private var overallProgress: Double {
        let stepShare = 1.0 / Double(SmartCareModel.Step.allCases.count)
        let inStep = model.currentStep == .junk ? (model.cleanup.progress.fraction ?? 0) : 0.5
        return (Double(model.currentStep.rawValue) + inStep) * stepShare
    }
}

private struct SmartCareResultsView: View {
    let model: SmartCareModel
    @Environment(AppModel.self) private var app
    private let module = AppModule.smartCare

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 26) {
                HealthGauge(score: model.healthScore, theme: module.theme)
                    .frame(width: 128, height: 128)
                VStack(alignment: .leading, spacing: 8) {
                    Text(headline).screenTitle()
                    Text("Here is what Smart Care found. Review any card, then click Run.").screenSubtitle()
                }
                Spacer()
            }
            .padding(.top, 64)
            .padding(.horizontal, 44)

            HStack(alignment: .top, spacing: 18) {
                cleanupCard
                protectionCard
                storageCard
            }
            .padding(.horizontal, 44)
            .padding(.top, 30)

            Spacer(minLength: 20)
            HStack(spacing: 28) {
                PillButton(title: "Start Over", symbol: "arrow.counterclockwise") { model.reset() }
                ScanButton(title: "Run", theme: module.theme) { model.run() }
                    .disabled(model.cleanup.selection.isEmpty)
                    .opacity(model.cleanup.selection.isEmpty ? 0.5 : 1)
                Color.clear.frame(width: 110, height: 1)
            }
            .padding(.bottom, 34)
        }
    }

    private var headline: LocalizedStringResource {
        switch model.healthScore {
        case 85...: "Your Mac is in great shape"
        case 60..<85: "Your Mac could use some care"
        default: "Your Mac needs attention"
        }
    }

    private var cleanupCard: some View {
        ResultCard(title: "Cleanup", symbol: "bubbles.and.sparkles.fill", theme: module.theme) {
            Text(formatBytes(model.cleanup.selectedSize))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text("of junk will be removed")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(CleanupCategory.allCases) { category in
                    let size = model.cleanup.size(selectedIn: category)
                    HStack {
                        Text(category.title)
                        Spacer()
                        Text(size > 0 ? formatBytes(size) : "—")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(.top, 10)
        } footer: {
            PillButton(title: "Review", symbol: "list.bullet") { model.cleanup.reviewing = .systemJunk }
                .disabled(model.cleanup.result.totalSize == 0)
        }
    }

    private var protectionCard: some View {
        ResultCard(title: "Protection", symbol: "checkmark.shield.fill", theme: module.theme) {
            let enabled = model.security.filter { $0.state == .enabled }.count
            Text("\(enabled)/\(model.security.count)")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text("built-in protections on")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.security) { result in
                    HStack(spacing: 8) {
                        Image(systemName: result.state == .enabled ? "checkmark.circle.fill" : result.state == .disabled ? "exclamationmark.triangle.fill" : "questionmark.circle")
                            .foregroundStyle(result.state == .disabled ? Color(hex: 0xFFD43B) : .white)
                        Text(result.check.title)
                            .lineLimit(1)
                        Spacer()
                        if result.state == .disabled, let url = result.check.settingsURL {
                            Button("Fix") { NSWorkspace.shared.open(url) }
                                .buttonStyle(.plain)
                                .foregroundStyle(Color(hex: 0xFFD43B))
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .help(Text(result.check.advice))
                }
            }
            .padding(.top, 10)
        } footer: {
            if let version = model.xprotectVersion {
                Text("Apple XProtect definitions \(version)")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    private var storageCard: some View {
        ResultCard(title: "Storage", symbol: "internaldrive.fill", theme: module.theme) {
            if let disk = model.disk {
                Text(formatBytes(disk.available))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("available on \(disk.name)")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.15))
                        Capsule()
                            .fill(LinearGradient(colors: [.white, module.theme.glow], startPoint: .leading, endPoint: .trailing))
                            .frame(width: proxy.size.width * disk.usedFraction)
                    }
                }
                .frame(height: 10)
                .padding(.top, 14)
                Text("\(formatBytes(disk.used)) used of \(formatBytes(disk.total))")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                    .padding(.top, 6)
            }
        } footer: {
            PillButton(title: "Open Space Lens", symbol: "circle.hexagongrid.fill") { app.selection = .spaceLens }
        }
    }
}

private struct ResultCard<Content: View, Footer: View>: View {
    let title: LocalizedStringResource
    let symbol: String
    let theme: ModuleTheme
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                FeatureBadge(symbol: symbol, theme: theme, size: 30)
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            }
            .padding(.bottom, 12)
            content
            Spacer(minLength: 14)
            footer
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 290, alignment: .topLeading)
        .glassPanel(cornerRadius: 22)
    }
}

/// Circular gauge showing the health score.
struct HealthGauge: View {
    let score: Int
    let theme: ModuleTheme

    var body: some View {
        ZStack {
            ProgressRing(fraction: Double(score) / 100, theme: theme, lineWidth: 10)
            VStack(spacing: 0) {
                Text("\(score)")
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Health")
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}
