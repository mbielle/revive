import AppKit
import LucentKit
import SwiftUI

/// App-wide state: navigation, settings and the long-lived model of each module.
@MainActor @Observable
final class AppModel {
    var selection: AppModule = .smartCare
    var hasFullDiskAccess = SystemStatus.hasFullDiskAccess()
    var showsAccessGuide = false

    /// Simulation mode: every flow runs normally but nothing is removed from disk.
    var dryRun: Bool {
        didSet { UserDefaults.standard.set(dryRun, forKey: Keys.dryRun) }
    }

    /// Folders the user never wants touched.
    var exclusions: [String] {
        didSet { UserDefaults.standard.set(exclusions, forKey: Keys.exclusions) }
    }

    @ObservationIgnored lazy var cleanup = CleanupModel(app: self, categories: Set(CleanupCategory.allCases), module: .cleanup)
    @ObservationIgnored lazy var smartCare = SmartCareModel(app: self)
    @ObservationIgnored lazy var spaceLens = SpaceLensModel(app: self)
    @ObservationIgnored lazy var activity = ActivityModel()

    private enum Keys {
        static let dryRun = "dryRun"
        static let exclusions = "exclusions"
    }

    init() {
        // Simulation can be forced from the command line: `open Lucent.app --args -dryRun YES`.
        dryRun = UserDefaults.standard.bool(forKey: Keys.dryRun)
        exclusions = UserDefaults.standard.stringArray(forKey: Keys.exclusions) ?? []
        #if DEBUG
        // Development helpers: `--args -module cleanup -autoScan YES` opens a module and scans it.
        if let raw = UserDefaults.standard.string(forKey: "module"), let module = AppModule(rawValue: raw) {
            selection = module
            if UserDefaults.standard.bool(forKey: "autoScan") {
                Task { @MainActor in
                    switch module {
                    case .cleanup: cleanup.scan()
                    case .smartCare: smartCare.scan()
                    case .spaceLens: spaceLens.scan()
                    default: break
                    }
                }
            }
        }
        #endif
    }

    var safetyGuard: SafetyGuard {
        SafetyGuard(userExclusions: exclusions.map { URL(filePath: $0) })
    }

    func remover() -> Remover {
        Remover(safetyGuard: safetyGuard, dryRun: dryRun)
    }

    /// Bundle id → name of every app currently running.
    func runningApps() -> [String: String] {
        var apps: [String: String] = [:]
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier { apps[id] = app.localizedName ?? id }
        }
        return apps
    }

    func refreshAccess() {
        hasFullDiskAccess = SystemStatus.hasFullDiskAccess()
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    func record(_ report: RemovalReport, module: AppModule) {
        guard report.removedCount > 0 || !report.failures.isEmpty else { return }
        let entry = ActivityEntry(module: module.rawValue, freedBytes: report.freedBytes, itemCount: report.removedCount,
                                  failureCount: report.failures.count, wasSimulated: report.wasSimulated)
        Task {
            try? await ActivityLog.shared.append(entry)
            await activity.reload()
        }
    }
}
