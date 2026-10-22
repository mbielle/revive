import AppKit
import LucentKit
import SwiftUI

@MainActor @Observable
final class ApplicationsModel {
    enum Phase: Equatable { case idle, scanning, ready, removing }
    enum Section: Hashable { case uninstaller, updater, leftovers, installers }
    enum Filter: Hashable { case all, unused, large, appStore, homebrew }
    enum Sort: Hashable { case name, size, lastUsed }

    private(set) var phase: Phase = .idle
    private(set) var apps: [InstalledApp] = []
    private(set) var updates: [AppUpdate] = []
    private(set) var orphans: [CleanupItem] = []
    private(set) var installers: [CleanupItem] = []
    private(set) var checkingUpdates = false
    private(set) var upgrading: Set<String> = []
    private(set) var lastReport: RemovalReport?

    var section: Section?
    var filter: Filter = .all
    var sort: Sort = .size
    var search = ""
    /// App ids checked in the uninstaller.
    var selectedApps: Set<String> = []
    /// Item ids checked in the leftovers and installers lists.
    var selectedFiles: Set<String> = []
    /// Files prepared for the uninstall review sheet.
    var uninstallPlan: [(app: InstalledApp, files: [CleanupItem])] = []
    var planSelection: Set<String> = []
    var showsUninstallReview = false

    @ObservationIgnored unowned let app: AppModel

    init(app: AppModel) {
        self.app = app
    }

    // MARK: Scanning

    func scan() {
        phase = .scanning
        Task {
            let safety = app.safetyGuard
            let running = Set(app.runningApps().keys).union([Bundle.main.bundleIdentifier ?? ""])
            let (apps, orphans, installers) = await Task.detached(priority: .userInitiated) {
                let apps = await AppInventory(home: safety.home).scan()
                let finder = LeftoverFinder(safetyGuard: safety)
                return (apps, finder.orphans(installed: apps, runningBundleIDs: running), finder.installers())
            }.value
            self.apps = apps.filter { !$0.isApple }
            self.orphans = orphans
            self.installers = installers
            selectedApps = []
            selectedFiles = []
            phase = .ready
            checkUpdates()
        }
    }

    /// Opens the updater, scanning first if needed (used from Smart Care).
    func openUpdater() {
        section = .updater
        if phase == .idle { scan() }
    }

    func checkUpdates() {
        guard !checkingUpdates else { return }
        checkingUpdates = true
        let apps = apps
        Task {
            updates = await UpdateChecker().check(apps)
            checkingUpdates = false
        }
    }

    // MARK: Uninstaller

    var visibleApps: [InstalledApp] {
        var list = apps
        switch filter {
        case .all: break
        case .unused: list = list.filter { $0.isUnused() }
        case .large: list = list.filter { $0.size > 500_000_000 }
        case .appStore: list = list.filter { $0.source == .appStore }
        case .homebrew: list = list.filter { $0.homebrewToken != nil }
        }
        if !search.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(search) || ($0.bundleID ?? "").localizedCaseInsensitiveContains(search) }
        }
        switch sort {
        case .name: list.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .size: list.sort { $0.size > $1.size }
        case .lastUsed: list.sort { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
        }
        return list
    }

    var totalAppsSize: Int64 { apps.reduce(0) { $0 + $1.size } }
    var unusedApps: [InstalledApp] { apps.filter { $0.isUnused() } }
    var selectedAppsSize: Int64 { apps.filter { selectedApps.contains($0.id) }.reduce(0) { $0 + $1.size } }

    func toggleApp(_ app: InstalledApp) {
        if selectedApps.contains(app.id) { selectedApps.remove(app.id) } else { selectedApps.insert(app.id) }
    }

    /// Collects every file of the checked apps and opens the review sheet.
    func prepareUninstall() {
        let chosen = apps.filter { selectedApps.contains($0.id) }
        let finder = LeftoverFinder(safetyGuard: app.safetyGuard)
        uninstallPlan = chosen.map { ($0, finder.files(for: $0)) }
        planSelection = Set(uninstallPlan.flatMap(\.files).map(\.id))
        showsUninstallReview = true
    }

    var planSize: Int64 {
        uninstallPlan.flatMap(\.files).filter { planSelection.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    func confirmUninstall() {
        showsUninstallReview = false
        let items = uninstallPlan.flatMap(\.files).filter { planSelection.contains($0.id) }
        let bundles = Set(uninstallPlan.map(\.app.url))
        phase = .removing
        Task {
            // Quit the apps first so they don't recreate their files.
            if !app.dryRun {
                for running in NSWorkspace.shared.runningApplications where running.bundleURL.map(bundles.contains) == true {
                    running.terminate()
                }
                try? await Task.sleep(for: .seconds(1))
            }
            let report = await WorkspaceRemover.recycle(items, policy: .appRemoval, safetyGuard: app.safetyGuard, dryRun: app.dryRun)
            finish(report, module: .applications)
            if !report.wasSimulated {
                let failed = Set(report.failures.map(\.path))
                let removed = Set(items.map(\.id)).filter { id in !failed.contains { $0.hasPrefix(id) } }
                apps.removeAll { removed.contains($0.id) }
            }
            selectedApps = []
            uninstallPlan = []
        }
    }

    // MARK: Leftovers and installers

    func removeFiles(_ items: [CleanupItem], policy: SafetyGuard.Policy) {
        let chosen = items.filter { selectedFiles.contains($0.id) }
        guard !chosen.isEmpty else { return }
        phase = .removing
        Task {
            let report = await WorkspaceRemover.recycle(chosen, policy: policy, safetyGuard: app.safetyGuard, dryRun: app.dryRun)
            finish(report, module: .applications)
            if !report.wasSimulated {
                let failed = Set(report.failures.map(\.path))
                let removed = Set(chosen.map(\.id)).filter { !failed.contains($0) }
                orphans.removeAll { removed.contains($0.id) }
                installers.removeAll { removed.contains($0.id) }
            }
            selectedFiles.subtract(chosen.map(\.id))
        }
    }

    private func finish(_ report: RemovalReport, module: AppModule) {
        lastReport = report
        app.record(report, module: module)
        phase = .ready
    }

    // MARK: Updates

    func update(_ update: AppUpdate) {
        if let token = update.app.homebrewToken, let brew = UpdateChecker.brewExecutable {
            upgrading.insert(update.id)
            Task {
                let status = await Task.detached {
                    let process = Process()
                    process.executableURL = brew
                    process.arguments = ["upgrade", "--cask", token]
                    process.standardOutput = FileHandle.nullDevice
                    process.standardError = FileHandle.nullDevice
                    guard (try? process.run()) != nil else { return Int32(-1) }
                    process.waitUntilExit()
                    return process.terminationStatus
                }.value
                upgrading.remove(update.id)
                if status == 0 { updates.removeAll { $0.id == update.id } }
            }
        } else if update.app.source == .appStore, let link = update.link {
            NSWorkspace.shared.open(link)
        } else {
            // Sparkle apps update themselves: open the app, it offers the new version.
            NSWorkspace.shared.openApplication(at: update.app.url, configuration: .init())
        }
    }
}
