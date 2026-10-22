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
    /// Run the tune-up tasks together with the cleanup.
    var includeTuneUp = true
    private(set) var tuneUpResult: PrivilegedResult?

    let cleanup: CleanupModel
    @ObservationIgnored unowned let app: AppModel
    @ObservationIgnored private var task: Task<Void, Never>?

    init(app: AppModel) {
        self.app = app
        cleanup = CleanupModel(app: app, categories: Set(CleanupCategory.allCases), module: .smartCare)
    }

    /// Maintenance run by Checkup: no password prompt unless the helper is installed.
    var tuneUpTasks: [MaintenanceTask] {
        app.privileged.helperState == .enabled ? [.freeMemory, .flushDNS, .resetQuickLook] : [.resetQuickLook]
    }

    func scan() {
        task?.cancel()
        phase = .scanning
        task = Task {
            currentStep = .junk
            await cleanup.runScan()
            guard !Task.isCancelled else { return }

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
            updates = await Task.detached(priority: .userInitiated) {
                var inventory = AppInventory()
                inventory.measuresSizes = false
                return await UpdateChecker().check(inventory.scan())
            }.value
            guard !Task.isCancelled else { return }
            phase = .results
        }
    }

    func stop() {
        task?.cancel()
        cleanup.stop()
        phase = .idle
    }

    func run() {
        phase = .running
        task = Task {
            if includeTuneUp && !app.dryRun {
                let tasks = tuneUpTasks
                let admin = tasks.compactMap(\.privilegedCommand)
                if !admin.isEmpty { tuneUpResult = await app.privileged.run(admin) }
                for task in tasks where task.privilegedCommand == nil {
                    _ = await Task.detached { task.runAsUser() }.value
                }
            }
            if !cleanup.selection.isEmpty {
                await cleanup.runClean()
            } else {
                cleanup.markNothingToClean(simulated: app.dryRun)
            }
            phase = .done
        }
    }

    func reset() {
        cleanup.reset()
        phase = .idle
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
