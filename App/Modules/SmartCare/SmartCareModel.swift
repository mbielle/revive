import LucentKit
import SwiftUI

/// One-click checkup: looks for junk, checks the Mac's protections and measures the disk.
@MainActor @Observable
final class SmartCareModel {
    enum Phase: Equatable { case idle, scanning, results, running, done }

    enum Step: Int, CaseIterable, Identifiable {
        case junk, security, storage
        var id: Int { rawValue }

        var title: LocalizedStringResource {
            switch self {
            case .junk: "Looking for junk"
            case .security: "Checking protections"
            case .storage: "Analyzing storage"
            }
        }
    }

    private(set) var phase: Phase = .idle
    private(set) var currentStep: Step = .junk
    private(set) var security: [SecurityCheckResult] = []
    private(set) var xprotectVersion: String?
    private(set) var disk: DiskSpace?

    let cleanup: CleanupModel
    @ObservationIgnored private var task: Task<Void, Never>?

    init(app: AppModel) {
        cleanup = CleanupModel(app: app, categories: Set(CleanupCategory.allCases), module: .smartCare)
    }

    func scan() {
        task?.cancel()
        phase = .scanning
        task = Task {
            currentStep = .junk
            await cleanup.runScan()
            guard !Task.isCancelled else { return }

            currentStep = .security
            security = await SystemStatus.securityChecks()
            xprotectVersion = SystemStatus.xprotectVersion()
            guard !Task.isCancelled else { return }

            currentStep = .storage
            disk = SystemStatus.startupDisk()
            try? await Task.sleep(for: .milliseconds(400))
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
            await cleanup.runClean()
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
        score -= min(30, junkGB * 2)
        score -= Double(disabledProtections.count) * 12
        if let disk {
            if disk.usedFraction > 0.95 { score -= 25 } else if disk.usedFraction > 0.85 { score -= 12 }
        }
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
