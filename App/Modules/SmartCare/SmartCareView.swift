import ReviveKit
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
    @Bindable var model: SmartCareModel
    @Environment(AppModel.self) private var app
    private let module = AppModule.smartCare

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 26) {
                HealthGauge(score: model.healthScore, theme: module.theme)
                    .frame(width: 118, height: 118)
                VStack(alignment: .leading, spacing: 8) {
                    Text(headline).screenTitle().lineLimit(1).minimumScaleFactor(0.6)
                    if let disk = model.disk {
                        Text("\(formatBytes(disk.available)) available on \(disk.name). Review any card, then click Run.").screenSubtitle()
                    }
                }
                Spacer()
            }
            .padding(.top, 60)
            .padding(.horizontal, 44)

            Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                GridRow {
                    cleanupCard
                    protectionCard
                }
                GridRow {
                    performanceCard
                    updatesCard
                }
            }
            .padding(.horizontal, 44)
            .padding(.top, 24)

            Spacer(minLength: 16)
            HStack(spacing: 28) {
                PillButton(title: "Start Over", symbol: "arrow.counterclockwise") { model.reset() }
                ScanButton(title: "Run", theme: module.theme) { model.run() }
                    .disabled(model.cleanup.selection.isEmpty && !model.includeTuneUp)
                PillButton(title: "Storage Map", symbol: "circle.hexagongrid.fill") { app.selection = .spaceLens }
            }
            .padding(.bottom, 28)
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
            BigValue(value: formatBytes(model.cleanup.selectedSize), caption: "of junk will be removed")
        } footer: {
            PillButton(title: "Review", symbol: "list.bullet") { model.cleanup.reviewing = .systemJunk }
                .disabled(model.cleanup.result.totalSize == 0)
        }
    }

    private var protectionCard: some View {
        let enabled = model.security.filter { $0.state == .enabled }.count
        let malware = model.threats.filter(\.isMalware).count
        return ResultCard(title: "Security", symbol: "checkmark.shield.fill", theme: module.theme) {
            if malware > 0 {
                BigValue(value: "\(malware)", caption: malware == 1 ? "threat found" : "threats found", alert: true)
            } else {
                BigValue(value: "\(enabled)/\(model.security.count)", caption: "built-in protections on, no malware")
            }
            HStack(spacing: 10) {
                ForEach(model.security) { result in
                    Label {
                        Text(result.check.title).lineLimit(1)
                    } icon: {
                        Image(systemName: result.state == .enabled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(result.state == .disabled ? Color(hex: 0xFFD43B) : .white)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .help(Text(result.check.advice))
                }
            }
            .padding(.top, 4)
        } footer: {
            HStack {
                if let fix = model.disabledProtections.first, let url = fix.check.settingsURL {
                    PillButton(title: "Turn On \(fix.check.title)", symbol: "wrench.fill") { NSWorkspace.shared.open(url) }
                }
                if !model.threats.isEmpty {
                    PillButton(title: "Review Threats", symbol: "ladybug.fill") { app.selection = .protection; app.protection.open(.malware) }
                }
            }
        }
    }

    private var performanceCard: some View {
        ResultCard(title: "Optimization", symbol: "bolt.fill", theme: module.theme) {
            BigValue(value: "\(Int((model.memory?.usedFraction ?? 0) * 100))%", caption: "of memory in use")
            Toggle(isOn: $model.includeTuneUp) {
                Text("Tune up: \(model.tuneUpTasks.map { $0.title.resolved }.joined(separator: ", "))")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.8)).lineLimit(2)
            }
            .toggleStyle(.checkbox)
            .padding(.top, 4)
        } footer: {
            PillButton(title: "More Tasks", symbol: "wrench.and.screwdriver.fill") { app.selection = .performance; app.performance.open(.maintenance) }
        }
    }

    private var updatesCard: some View {
        ResultCard(title: "Apps", symbol: "arrow.down.app.fill", theme: module.theme) {
            BigValue(value: "\(model.updates.count)", caption: model.updates.isEmpty ? "apps up to date"
                     : model.updates.count == 1 ? "app update available" : "app updates available")
            Text(model.updates.prefix(3).map(\.app.name).joined(separator: ", "))
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
        } footer: {
            PillButton(title: "Open Updater", symbol: "arrow.down.circle.fill") { app.selection = .applications; app.applications.openUpdater() }
                .disabled(model.updates.isEmpty)
        }
    }
}

private struct BigValue: View {
    let value: String
    let caption: LocalizedStringResource
    var alert = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(alert ? Color(hex: 0xFFD43B) : .white)
                .contentTransition(.numericText())
            Text(caption).font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
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
            .padding(.bottom, 8)
            content
            Spacer(minLength: 10)
            footer
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
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
