import LucentKit
import SwiftUI

/// Drives the scan → review → clean flow. Also used by Smart Care for its junk step.
@MainActor @Observable
final class CleanupModel {
    enum Phase: Equatable {
        case idle, scanning, results, cleaning, done
    }

    private(set) var phase: Phase = .idle
    private(set) var progress = ScanProgress(currentPath: "", bytesFound: 0)
    private(set) var result = CleanupScanResult()
    private(set) var report: RemovalReport?
    private(set) var errorMessage: String?
    var selection: Set<String> = []
    /// Category opened in the review screen, nil when showing the summary.
    var reviewing: CleanupCategory?
    /// Category to open once the running scan finishes (from My Tools).
    var pendingReview: CleanupCategory?

    let categories: Set<CleanupCategory>
    let module: AppModule
    @ObservationIgnored unowned let app: AppModel
    @ObservationIgnored private var task: Task<Void, Never>?

    init(app: AppModel, categories: Set<CleanupCategory>, module: AppModule) {
        self.app = app
        self.categories = categories
        self.module = module
    }

    // MARK: Actions

    func scan() {
        task?.cancel()
        phase = .scanning
        progress = ScanProgress(currentPath: "", bytesFound: 0)
        report = nil
        errorMessage = nil
        reviewing = nil
        task = Task { await runScan() }
    }

    /// Scans and waits for the result; used by Smart Care to chain its steps.
    func runScan() async {
        phase = .scanning
        let scanner = CleanupScanner(rules: (try? RuleCatalog.bundled()) ?? [], safetyGuard: app.safetyGuard, runningApps: app.runningApps())
        let categories = categories
        let report = progressHandler()
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try await scanner.scan(categories: categories, progress: report)
            }.value
            guard !Task.isCancelled else { return }
            self.result = result
            selection = result.defaultSelection
            phase = .results
            if let pending = pendingReview, result.totalSize(in: pending) > 0 { reviewing = pending }
            pendingReview = nil
        } catch is CancellationError {
            phase = .idle
        } catch {
            errorMessage = error.localizedDescription
            phase = .idle
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        phase = .idle
    }

    /// Forwards progress from background work to the UI without keeping the model alive.
    private func progressHandler() -> @Sendable (ScanProgress) -> Void {
        { [weak self] progress in
            Task { @MainActor in self?.progress = progress }
        }
    }

    func clean() {
        task?.cancel()
        task = Task { await runClean() }
    }

    func runClean() async {
        let items = result.allItems.filter { selection.contains($0.id) }
        guard !items.isEmpty else { return }
        phase = .cleaning
        progress = ScanProgress(currentPath: "", bytesFound: 0, fraction: 0)
        let remover = app.remover()
        let onProgress = progressHandler()
        let report = await Task.detached(priority: .userInitiated) {
            await remover.remove(items, policy: .automatic, progress: onProgress)
        }.value
        self.report = report
        app.record(report, module: module)
        phase = .done
    }

    /// Ends a run where nothing was selected for removal (Smart Care with only a tune-up).
    func markNothingToClean(simulated: Bool) {
        var report = RemovalReport()
        report.wasSimulated = simulated
        self.report = report
        phase = .done
    }

    func reset() {
        task?.cancel()
        phase = .idle
        result = CleanupScanResult()
        selection = []
        reviewing = nil
        report = nil
    }

    // MARK: Selection

    func size(selectedIn category: CleanupCategory) -> Int64 {
        result.results(in: category).flatMap(\.items).filter { selection.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    var selectedSize: Int64 {
        result.allItems.filter { selection.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    func state(of items: [CleanupItem]) -> CheckBox.State {
        let selected = items.filter { selection.contains($0.id) }.count
        return selected == 0 ? .off : selected == items.count ? .on : .mixed
    }

    func toggle(_ items: [CleanupItem]) {
        if state(of: items) == .on {
            selection.subtract(items.map(\.id))
        } else {
            selection.formUnion(items.map(\.id))
        }
    }
}

extension CleanupCategory {
    var title: LocalizedStringResource {
        switch self {
        case .systemJunk: "System Junk"
        case .aiClutter: "AI Clutter"
        case .mailAttachments: "Mail Attachments"
        case .trashBins: "Trash Bins"
        }
    }

    var subtitle: LocalizedStringResource {
        switch self {
        case .systemJunk: "Caches, logs and leftovers apps don't need."
        case .aiClutter: "Caches and downloads of AI apps and tools."
        case .mailAttachments: "Attachments Mail saved on this Mac."
        case .trashBins: "Files waiting in your Trash bins."
        }
    }

    var symbol: String {
        switch self {
        case .systemJunk: "xmark.bin.fill"
        case .aiClutter: "sparkles"
        case .mailAttachments: "envelope.fill"
        case .trashBins: "trash.fill"
        }
    }
}
