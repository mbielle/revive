import ReviveKit
import SwiftUI

/// One-click checkup: junk, protections, performance and app updates, then one Run button.
@MainActor @Observable
final class SmartCareModel {
    enum Phase: Equatable { case idle, scanning, results, running, done }

    enum Step: Int, CaseIterable, Identifiable {
        case junk, security, performance, updates
        var id: Int { rawValue }

        var title: LocalizedStringResource {
            switch self {
            case .junk: "Looking for junk"
            case .security: "Checking protections"
            case .performance: "Checking performance"
            case .updates: "Looking for app updates"
            }
        }
    }

    private(set) var phase: Phase = .idle
    private(set) var currentStep: Step = .junk
    private(set) var security: [SecurityCheckResult] = []
    private(set) var xprotectVersion: String?
    private(set) var disk: DiskSpace?
    private(set) var memory: MemoryUsage?
    private(set) var updates: [AppUpdate] = []
    private(set) var threats: [Threat] = []
    /// What Run does, card by card.
    var includeTuneUp = true
    var includeThreats = true
    var includeUpdates = true
    /// What the last Run did, shown on the done screen.
    private(set) var summary = RunSummary()
    /// The part of Run in progress, shown while it works.
    private(set) var runningStep: LocalizedStringResource = "Taking care of your Mac…"
    private(set) var scanError: String?

    struct RunSummary {
        var cleanup: RemovalReport?
        var tasks: [(task: MaintenanceTask, error: String?)] = []
        var threats: RemovalReport?
        var updated: [String] = []
        var updateFailures: [(name: String, error: String)] = []
        /// App Store and Sparkle apps: Revive opens them, they update themselves.
        var manualUpdates: [AppUpdate] = []
        var simulated = false
    }

    let cleanup: CleanupModel
    @ObservationIgnored unowned let app: AppModel
    @ObservationIgnored private var task: Task<Void, Never>?

    init(app: AppModel) {
        self.app = app
        cleanup = CleanupModel(app: app, categories: Set(CleanupCategory.allCases), module: .smartCare)
    }

    /// Maintenance run by Checkup. Administrator tasks share one password prompt without the helper.
    var tuneUpTasks: [MaintenanceTask] { MaintenanceTask.allCases.filter(\.isRecommended) }

    /// Updates Run installs itself (Homebrew casks); the others are opened afterwards.
    var automaticUpdates: [AppUpdate] { updates.filter { $0.app.homebrewToken != nil } }

    var canRun: Bool {
        !cleanup.selection.isEmpty || includeTuneUp || (includeThreats && threats.contains(where: \.isMalware)) || (includeUpdates && !updates.isEmpty)
    }

    func scan() {
        task?.cancel()
        phase = .scanning
        scanError = nil
        task = Task {
            currentStep = .junk
            await cleanup.runScan()
            guard !Task.isCancelled else { return }
            scanError = cleanup.errorMessage

            currentStep = .security
            async let checks = SystemStatus.securityChecks()
            async let found = app.protection.quickThreatScan()
            security = await checks
            threats = await found
            xprotectVersion = SystemStatus.xprotectVersion()
            guard !Task.isCancelled else { return }

            currentStep = .performance
            disk = SystemStatus.startupDisk()
            memory = SystemMetrics.memory()
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            currentStep = .updates
            let appRoots = app.appRoots
            updates = await Task.detached(priority: .userInitiated) {
                var inventory = AppInventory()
                inventory.roots = appRoots
                inventory.measuresSizes = false
                return await UpdateChecker().check(inventory.scan())
            }.value
            guard !Task.isCancelled else { return }
            phase = .results
            #if DEBUG
            // `-autoRun YES` clicks Run once the scan is done, to test the whole flow.
            if UserDefaults.standard.bool(forKey: "autoRun") { run() }
            #endif
        }
    }

    func stop() {
        task?.cancel()
        cleanup.stop()
        phase = .idle
    }

    func run() {
        phase = .running
        summary = RunSummary(simulated: app.dryRun)
        task = Task {
            if includeTuneUp {
                runningStep = "Running maintenance tasks…"
                let tasks = tuneUpTasks
                await app.performance.runTasks(tasks)
                summary.tasks = tasks.map { task in
                    if case .failed(let reason) = app.performance.taskStates[task] { return (task, reason) }
                    return (task, nil)
                }
            }
            let malware = threats.filter(\.isMalware)
            if includeThreats && !malware.isEmpty {
                runningStep = "Removing threats…"
                // Only confirmed malware; other findings are left for review in Security.
                let report = await app.protection.remove(malware)
                app.record(report, module: .protection)
                summary.threats = report
                if !report.wasSimulated { threats = app.protection.remaining(of: threats) }
            }
            if includeUpdates && !updates.isEmpty {
                runningStep = "Updating apps…"
                for update in automaticUpdates {
                    if let error = await app.applications.upgrade(update) {
                        summary.updateFailures.append((update.app.name, error))
                    } else {
                        summary.updated.append(update.app.name)
                        updates.removeAll { $0.id == update.id }
                    }
                }
                summary.manualUpdates = updates.filter { $0.app.homebrewToken == nil }
            }
            if !cleanup.selection.isEmpty {
                runningStep = "Removing junk…"
                await cleanup.runClean()
                summary.cleanup = cleanup.report
            }
            phase = .done
        }
    }

    /// Opens an app that updates itself (Sparkle) or its App Store page.
    func openManualUpdate(_ update: AppUpdate) {
        app.applications.update(update)
    }

    func reset() {
        cleanup.reset()
        phase = .idle
    }

    /// Done: scan again so the score and cards show the Mac as it is now.
    func finish() {
        cleanup.reset()
        scan()
    }

    var disabledProtections: [SecurityCheckResult] {
        security.filter { $0.state == .disabled }
    }

    /// 0–100 summary of everything found; only meant as an at-a-glance indicator.
    var healthScore: Int {
        var score = 100.0
        let junkGB = Double(cleanup.result.recommendedSize) / 1_000_000_000
        score -= min(25, junkGB * 2)
        score -= Double(disabledProtections.count) * 10
        score -= Double(min(threats.count, 3)) * 15
        score -= Double(min(updates.count, 10))
        if let disk {
            if disk.usedFraction > 0.95 { score -= 20 } else if disk.usedFraction > 0.85 { score -= 10 }
        }
        if let memory, memory.usedFraction > 0.9 { score -= 5 }
        return max(5, Int(score.rounded()))
    }
}

extension SecurityCheck {
    var title: LocalizedStringResource {
        switch self {
        case .systemIntegrityProtection: "System Integrity Protection"
        case .gatekeeper: "Gatekeeper"
        case .fileVault: "FileVault disk encryption"
        case .firewall: "Firewall"
        }
    }

    var advice: LocalizedStringResource {
        switch self {
        case .systemIntegrityProtection: "Protects system files from being modified, even by administrators."
        case .gatekeeper: "Only allows apps from identified developers to open."
        case .fileVault: "Encrypts your disk so nobody can read it if your Mac is lost."
        case .firewall: "Blocks unwanted incoming network connections."
        }
    }

    /// Where the user can turn the protection on, when macOS has a settings pane for it.
    var settingsURL: URL? {
        switch self {
        case .fileVault: URL(string: "x-apple.systempreferences:com.apple.preference.security?FileVault")
        case .firewall: URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension?Firewall")
        case .gatekeeper: URL(string: "x-apple.systempreferences:com.apple.preference.security?Security")
        case .systemIntegrityProtection: nil
        }
    }
}
