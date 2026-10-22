import LucentKit
import SwiftUI

@MainActor @Observable
final class CloudModel {
    enum Phase: Equatable { case idle, scanning, ready, working }

    private(set) var phase: Phase = .idle
    private(set) var result = CloudScanResult()
    var provider: CloudProvider?
    var showsDuplicates = false
    var selection: Set<String> = []
    private(set) var message: String?

    @ObservationIgnored unowned let app: AppModel

    init(app: AppModel) {
        self.app = app
    }

    func scan() {
        phase = .scanning
        let home = app.safetyGuard.home
        Task {
            result = await Task.detached(priority: .userInitiated) { CloudScanner(home: home).scan() }.value
            selection = []
            phase = .ready
        }
    }

    func toggle(_ file: ClutterFile) {
        if selection.contains(file.id) { selection.remove(file.id) } else { selection.insert(file.id) }
    }

    /// Frees the downloaded copies; the files stay in the cloud.
    func removeLocalCopies(of provider: CloudProvider) {
        let chosen = provider.largestLocalFiles.filter { selection.contains($0.id) }
        guard !chosen.isEmpty else { return }
        if app.dryRun {
            message = String(localized: "Simulation: \(formatBytes(chosen.reduce(0) { $0 + $1.size })) of local copies would be freed.")
            selection = []
            return
        }
        phase = .working
        Task {
            var report = RemovalReport()
            for file in chosen {
                do {
                    try CloudScanner.removeLocalCopy(file.url)
                    report.removedCount += 1
                    report.freedBytes += file.size
                } catch {
                    report.failures.append(.init(path: file.url.path(percentEncoded: false), reason: error.localizedDescription))
                }
            }
            app.record(report, module: .cloudCleanup)
            message = report.failures.isEmpty
                ? String(localized: "\(formatBytes(report.freedBytes)) freed. The files are still in the cloud.")
                : String(localized: "\(report.failures.count) files could not be freed by their cloud app.")
            selection = []
            phase = .ready
            scan()
        }
    }

    func removeDuplicates() {
        let chosen = result.localDuplicates.filter { selection.contains($0.id) }
        guard !chosen.isEmpty else { return }
        phase = .working
        Task {
            let report = await WorkspaceRemover.recycle(chosen.map(\.asCleanupItem), policy: .userInitiated, safetyGuard: app.safetyGuard, dryRun: app.dryRun)
            app.record(report, module: .cloudCleanup)
            if !report.wasSimulated { result.localDuplicates.removeAll { chosen.contains($0) } }
            selection = []
            phase = .ready
        }
    }
}

struct CloudView: View {
    @Bindable var model: CloudModel
    @Environment(AppModel.self) private var app
    private let module = AppModule.cloudCleanup

    var body: some View {
        Group {
            switch model.phase {
            case .idle:
                ModuleLanding(module: module) {
                    ScanButton(title: "Scan", theme: module.theme) { model.scan() }
                }
            case .scanning:
                WorkingView(module: module, title: "Measuring your cloud folders…", progress: nil, detail: "~/Library/CloudStorage", stat: nil, onStop: nil)
            case .ready, .working:
                if let provider = model.provider {
                    ProviderScreen(model: model, provider: provider)
                } else if model.showsDuplicates {
                    DuplicatesScreen(model: model)
                } else {
                    overview
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.phase)
        .animation(.easeInOut(duration: 0.3), value: model.provider)
        .animation(.easeInOut(duration: 0.3), value: model.showsDuplicates)
    }

    @ViewBuilder
    private var overview: some View {
        let local = model.result.providers.reduce(0) { $0 + $1.localSize }
        if model.result.providers.isEmpty {
            VStack(spacing: 18) {
                HeroIllustration(style: .cloud, symbol: "icloud.slash.fill", theme: module.theme, size: 260)
                Text("No cloud storage found").screenTitle()
                Text(model.result.iCloudUnreadable
                     ? "iCloud Drive is protected by macOS. Grant Full Disk Access so Lucent can measure it."
                     : "Lucent looks at iCloud Drive and at Google Drive, OneDrive, Dropbox and Box folders in Finder.")
                    .screenSubtitle().multilineTextAlignment(.center).frame(maxWidth: 520)
                HStack {
                    if model.result.iCloudUnreadable {
                        PillButton(title: "Grant Full Disk Access", symbol: "lock.open.fill", prominent: true) { app.showsAccessGuide = true }
                    }
                    PillButton(title: "Scan Again", symbol: "arrow.counterclockwise") { model.scan() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            OverviewScreen(
                title: String(localized: "\(formatBytes(local)) of cloud files on this Mac"),
                subtitle: String(localized: "Free local copies you don't need right now: the files stay safe in the cloud.")
            ) {
                ForEach(model.result.providers) { provider in
                    OverviewTile(symbol: provider.name == "iCloud Drive" ? "icloud.fill" : "externaldrive.fill.badge.icloud",
                                 title: "\(provider.name)",
                                 subtitle: String(localized: "\(formatBytes(provider.totalSize)) in the cloud"),
                                 value: formatBytes(provider.localSize), theme: module.theme) { model.provider = provider }
                }
                OverviewTile(symbol: "doc.on.doc.fill", title: "Local Duplicates",
                             subtitle: String(localized: "Files in Downloads, Desktop or Documents also stored in the cloud."),
                             value: formatBytes(model.result.localDuplicates.reduce(0) { $0 + $1.size }), theme: module.theme) { model.showsDuplicates = true }
            } footer: {
                HStack(spacing: 14) {
                    PillButton(title: "Scan Again", symbol: "arrow.counterclockwise") { model.scan() }
                    if let message = model.message {
                        Text(message).font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
        }
    }
}

private struct ProviderScreen: View {
    @Bindable var model: CloudModel
    let provider: CloudProvider
    private let theme = AppModule.cloudCleanup.theme

    var body: some View {
        DetailScreen(title: "\(provider.name)", symbol: "icloud.fill", theme: theme, onBack: { model.provider = nil }) {
            PillButton(title: "Show in Finder", symbol: "folder") { NSWorkspace.shared.open(provider.root) }
        } content: {
            Text("Biggest files downloaded on this Mac. Removing the local copy keeps the file in the cloud; it downloads again when you open it.")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(provider.largestLocalFiles) { file in
                        FileItemRow(item: file.asCleanupItem, isSelected: model.selection.contains(file.id)) { model.toggle(file) }
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassPanel(cornerRadius: 20)
            .overlay { if provider.largestLocalFiles.isEmpty { EmptyState(symbol: "icloud.fill", message: "Everything is already online-only.") } }
        } bottom: {
            HStack {
                Spacer()
                ScanButton(title: "Free Up", theme: theme, diameter: 84, pulses: false) { model.removeLocalCopies(of: provider) }
                    .disabled(model.selection.isEmpty || model.phase == .working)
                    .opacity(model.selection.isEmpty ? 0.45 : 1)
            }
        }
    }
}

private struct DuplicatesScreen: View {
    @Bindable var model: CloudModel
    private let theme = AppModule.cloudCleanup.theme

    var body: some View {
        DetailScreen(title: "Local Duplicates", symbol: "doc.on.doc.fill", theme: theme, onBack: { model.showsDuplicates = false }) {
            EmptyView()
        } content: {
            Text("These files have a twin with the same name and size in your cloud storage. The local one goes to the Trash.")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.result.localDuplicates) { file in
                        FileItemRow(item: file.asCleanupItem, isSelected: model.selection.contains(file.id)) { model.toggle(file) }
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassPanel(cornerRadius: 20)
            .overlay { if model.result.localDuplicates.isEmpty { EmptyState(symbol: "checkmark.circle.fill", message: "No local duplicates.") } }
        } bottom: {
            HStack {
                Spacer()
                ScanButton(title: "Remove", theme: theme, diameter: 84, pulses: false) { model.removeDuplicates() }
                    .disabled(model.selection.isEmpty || model.phase == .working)
                    .opacity(model.selection.isEmpty ? 0.45 : 1)
            }
        }
    }
}
