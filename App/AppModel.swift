import AppKit
import ReviveKit
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
    @ObservationIgnored lazy var applications = ApplicationsModel(app: self)
    @ObservationIgnored lazy var performance = PerformanceModel(app: self)
    @ObservationIgnored lazy var protection = ProtectionModel(app: self)
    @ObservationIgnored lazy var clutter = ClutterModel(app: self)
    @ObservationIgnored lazy var cloud = CloudModel(app: self)
    @ObservationIgnored lazy var tools = ToolsModel()
    let scheduler = AutoScanScheduler()
    let updater = UpdaterModel()

    /// Shows the live monitor in the menu bar.
    var showsMenuBar: Bool {
        didSet { UserDefaults.standard.set(showsMenuBar, forKey: "showsMenuBar") }
    }
    let privileged = PrivilegedRunner()

    private enum Keys {
        static let dryRun = "dryRun"
        static let exclusions = "exclusions"
    }

    init() {
        // Simulation can be forced from the command line: `open Revive.app --args -dryRun YES`.
        dryRun = UserDefaults.standard.bool(forKey: Keys.dryRun)
        exclusions = UserDefaults.standard.stringArray(forKey: Keys.exclusions) ?? []
        showsMenuBar = UserDefaults.standard.object(forKey: "showsMenuBar") as? Bool ?? true
        #if DEBUG
        // `-assumeFullDiskAccess YES` hides the access prompts, for screenshots of a demo home.
        if UserDefaults.standard.bool(forKey: "assumeFullDiskAccess") { hasFullDiskAccess = true }
        #endif
        watchFullDiskAccess()
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "helperSelfTest") {
            Task { await Self.runHelperSelfTest() }
        }
        // Development helpers: `--args -module cleanup -autoScan YES` opens a module and scans it.
        if let raw = UserDefaults.standard.string(forKey: "module"), let module = AppModule(rawValue: raw) {
            selection = module
            if UserDefaults.standard.bool(forKey: "autoScan") {
                Task { @MainActor in
                    switch module {
                    case .cleanup: cleanup.scan()
                    case .smartCare: smartCare.scan()
                    case .spaceLens: spaceLens.scan()
                    case .applications: applications.scan()
                    case .performance: performance.scan()
                    case .protection: protection.scan()
                    case .myClutter: clutter.scan()
                    case .cloudCleanup: cloud.scan()
                    default: break
                    }
                    await openDebugSection(UserDefaults.standard.string(forKey: "section"), in: module)
                }
            }
        }
        #endif
    }

    #if DEBUG
    /// `-helperSelfTest YES` talks to a helper loaded in the user's launchd domain (no root) and
    /// logs the results: it exercises the real helper binary, launchd and the signature check.
    static func runHelperSelfTest() async {
        func call(_ command: PrivilegedCommand) async -> String {
            let connection = NSXPCConnection(machServiceName: helperServiceName, options: [])
            guard let result = await HelperClient.run(command, connection: connection) else { return "no connection" }
            return "exit \(result.exitCode): \(result.output.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))"
        }
        NSLog("HELPER-SELFTEST flushDNS -> %@", await call(.flushDNS))
        NSLog("HELPER-SELFTEST bootout com.apple.x -> %@", await call(.bootout(label: "com.apple.x")))
        NSLog("HELPER-SELFTEST trash /System -> %@", await call(.moveToTrash(paths: ["/System/Library"], uid: getuid())))
        NSLog("HELPER-SELFTEST bootout unknown -> %@", await call(.bootout(label: "io.github.mbielle.does-not-exist")))
        NSLog("HELPER-SELFTEST done")
    }

    /// `-section <name>` opens a detail screen once the module's scan is done.
    private func openDebugSection(_ name: String?, in module: AppModule) async {
        guard let name else { return }
        for _ in 0..<240 {
            try? await Task.sleep(for: .milliseconds(500))
            switch module {
            case .applications where applications.phase == .ready:
                applications.section = ["uninstaller": .uninstaller, "updater": .updater, "leftovers": .leftovers, "installers": .installers][name]
                if name == "review", let first = applications.visibleApps.first {
                    applications.selectedApps = [first.id]
                    applications.section = .uninstaller
                    applications.prepareUninstall()
                }
                return
            case .performance where performance.phase == .ready:
                performance.section = ["maintenance": .maintenance, "loginItems": .loginItems, "backgroundItems": .backgroundItems, "consumers": .consumers][name]
                return
            case .protection where protection.phase == .ready:
                protection.section = ["malware": .malware, "privacy": .privacy, "extensions": .extensions, "wifi": .wifi, "permissions": .permissions][name]
                return
            case .myClutter where clutter.phase == .ready:
                clutter.section = ["duplicates": .duplicates, "similar": .similar, "large": .large, "screenshots": .screenshots][name]
                return
            case .smartCare where smartCare.phase == .results:
                if name == "review" { smartCare.cleanup.reviewing = .systemJunk }
                return
            case .cleanup where cleanup.phase == .results:
                if name == "clean" { cleanup.clean() } else { cleanup.reviewing = CleanupCategory(rawValue: name) }
                return
            default:
                continue
            }
        }
    }
    #endif

    /// The folder scanned as the user's home. Debug builds accept `-home <path>` to work on a demo
    /// folder made by `scripts/make-demo-home.swift` instead of the real one.
    let home: URL = {
        #if DEBUG
        if let path = UserDefaults.standard.string(forKey: "home") { return URL(filePath: path, directoryHint: .isDirectory) }
        #endif
        return FileManager.default.homeDirectoryForCurrentUser
    }()

    /// Folders listed by the app inventory. A demo home (`-home`) only shows its own Applications folder.
    var appRoots: [URL] {
        home == FileManager.default.homeDirectoryForCurrentUser
            ? AppInventory(home: home).roots
            : [home.appending(path: "Applications")]
    }

    var safetyGuard: SafetyGuard {
        SafetyGuard(home: home, userExclusions: exclusions.map { URL(filePath: $0) })
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
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "assumeFullDiskAccess") { return }
        #endif
        let granted = SystemStatus.hasFullDiskAccess()
        if granted != hasFullDiskAccess {
            withAnimation(.spring(duration: 0.4)) { hasFullDiskAccess = granted }
        }
    }

    /// Checks every two seconds until access is granted, so the "Grant Full Disk Access" button
    /// disappears as soon as the switch is turned on in System Settings.
    private func watchFullDiskAccess() {
        Task { [weak self] in
            while let self, !self.hasFullDiskAccess {
                try? await Task.sleep(for: .seconds(2))
                self.refreshAccess()
            }
        }
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
