import ReviveKit
import SwiftUI

struct CleanupView: View {
    let model: CleanupModel
    private var module: AppModule { model.module }

    var body: some View {
        Group {
            switch model.phase {
            case .idle:
                ModuleLanding(module: module) {
                    if let error = model.errorMessage {
                        Text(error).font(.callout).foregroundStyle(.white.opacity(0.8))
                    }
                } action: {
                    ScanButton(title: "Scan", theme: module.theme) { model.scan() }
                }
            case .scanning:
                WorkingView(module: module, title: "Looking for junk…", progress: model.progress.fraction,
                            detail: model.progress.currentPath, stat: formatBytes(model.progress.bytesFound)) { model.stop() }
            case .results:
                if let category = model.reviewing {
                    CleanupReviewView(model: model, category: category)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    CleanupResultsView(model: model)
                        .transition(.opacity)
                }
            case .cleaning:
                WorkingView(module: module, title: "Cleaning…", progress: model.progress.fraction,
                            detail: model.progress.currentPath, stat: formatBytes(model.progress.bytesFound), onStop: nil)
            case .done:
                if let report = model.report {
                    CompletionView(module: module, report: report) { model.reset() }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.phase)
        .animation(.easeInOut(duration: 0.3), value: model.reviewing)
    }
}

/// Summary after a scan: one tile per category and the Clean button.
struct CleanupResultsView: View {
    @Bindable var model: CleanupModel
    @Environment(AppModel.self) private var app
    private var theme: ModuleTheme { model.module.theme }
    private var categories: [CleanupCategory] { CleanupCategory.allCases.filter { model.categories.contains($0) } }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                let recommended = model.result.recommendedSize
                let optional = model.result.totalSize - recommended
                if model.result.totalSize == 0 {
                    Text("Your Mac is already clean").screenTitle()
                    Text("Nothing worth removing was found.").screenSubtitle()
                } else {
                    Text("\(formatBytes(recommended)) of junk found").screenTitle()
                    if optional > 0 {
                        Text("Plus \(formatBytes(optional)) you may want to review, like downloaded AI models. Nothing is removed without your OK.")
                            .screenSubtitle()
                    } else {
                        Text("Review what will be removed or click Clean. Items go to the Trash first.").screenSubtitle()
                    }
                }
            }
            .multilineTextAlignment(.center)
            .padding(.top, 70)
            .padding(.horizontal, 40)

            if !app.hasFullDiskAccess && !model.result.unreadableLocations.isEmpty {
                AccessHint()
                    .padding(.top, 14)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)], spacing: 18) {
                ForEach(categories) { category in
                    CategoryTile(model: model, category: category)
                }
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 40)
            .padding(.top, 30)

            Spacer(minLength: 20)
            HStack(spacing: 28) {
                PillButton(title: "Start Over", symbol: "arrow.counterclockwise") { model.reset() }
                ScanButton(title: "Clean", theme: theme) { model.clean() }
                    .disabled(model.selection.isEmpty)
                    .opacity(model.selection.isEmpty ? 0.5 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatBytes(model.selectedSize))
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("selected").font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                }
                .frame(width: 110, alignment: .leading)
            }
            .padding(.bottom, 34)
        }
    }
}

struct CategoryTile: View {
    let model: CleanupModel
    let category: CleanupCategory
    @State private var hovering = false

    var body: some View {
        let total = model.result.totalSize(in: category)
        let items = model.result.results(in: category).flatMap(\.items)
        Button {
            model.reviewing = category
        } label: {
            HStack(spacing: 14) {
                CheckBox(state: total > 0 ? model.state(of: items) : .off) { model.toggle(items) }
                    .opacity(total > 0 ? 1 : 0)
                FeatureBadge(symbol: category.symbol, theme: model.module.theme, size: 46)
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(category.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    let selected = model.size(selectedIn: category)
                    Text(total > 0 ? formatBytes(selected) : String(localized: "Clean"))
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    if total > selected {
                        Text("of \(formatBytes(total))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    if total > 0 {
                        Text("Review \(Image(systemName: "chevron.right"))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(hovering ? 1 : 0.7))
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 92)
            .glassPanel(cornerRadius: 20)
            .scaleEffect(hovering ? 1.015 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .disabled(total == 0)
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.25), value: hovering)
    }
}

/// Shown at the end of a cleanup.
struct CompletionView: View {
    let module: AppModule
    let report: RemovalReport
    let onDone: () -> Void
    @State private var showFailures = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            HStack(spacing: 50) {
                ZStack {
                    HeroIllustration(style: .disc, symbol: "checkmark", theme: module.theme, size: 300)
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 14) {
                    Text(report.wasSimulated ? "Simulation complete" : "All done!").screenTitle()
                    Text(formatBytes(report.freedBytes))
                        .font(.system(size: 54, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(report.wasSimulated
                         ? "would have been freed. Nothing was deleted because simulation mode is on."
                         : "freed. Items you moved to the Trash can still be restored until you empty it.")
                        .screenSubtitle()
                        .frame(maxWidth: 420, alignment: .leading)
                    if !report.failures.isEmpty {
                        Button {
                            showFailures.toggle()
                        } label: {
                            Label("\(report.failures.count) items could not be removed", systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showFailures) { FailureList(failures: report.failures) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 40)
            Spacer(minLength: 20)
            ScanButton(title: "Done", theme: module.theme, pulses: false, action: onDone)
                .padding(.bottom, 34)
        }
    }
}

/// What the last removal did, with the items that failed one click away.
struct ReportBanner: View {
    let report: RemovalReport
    @State private var showFailures = false

    var body: some View {
        HStack(spacing: 12) {
            if report.removedCount > 0 || report.failures.isEmpty {
                Text(report.wasSimulated ? "Simulated: \(formatBytes(report.freedBytes))" : "Moved \(formatBytes(report.freedBytes)) to the Trash")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.75))
            }
            if !report.failures.isEmpty {
                Button {
                    showFailures.toggle()
                } label: {
                    Label("\(report.failures.count) items could not be removed", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xFFD43B))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showFailures) { FailureList(failures: report.failures) }
            }
        }
    }
}

struct FailureList: View {
    let failures: [RemovalReport.Failure]

    var body: some View {
        List(failures) { failure in
            VStack(alignment: .leading, spacing: 2) {
                Text(failure.path).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                Text(failure.reason).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(width: 460, height: 260)
    }
}

/// Explains that some locations could not be read without Full Disk Access.
struct AccessHint: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Button {
            app.showsAccessGuide = true
        } label: {
            Label("Some folders are protected by macOS. Grant Full Disk Access to scan everything.", systemImage: "lock.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(.black.opacity(0.22)))
        }
        .buttonStyle(.plain)
    }
}
