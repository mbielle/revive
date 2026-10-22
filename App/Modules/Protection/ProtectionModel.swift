import AppKit
import ReviveKit
import SwiftUI

@MainActor @Observable
final class ProtectionModel {
    enum Phase: Equatable { case idle, scanning, ready, removing }
    enum Section: Hashable { case malware, privacy, extensions, wifi, permissions }

    private(set) var phase: Phase = .idle
    var section: Section?
    var deepScan = false
    private(set) var progress = ScanProgress(currentPath: "", bytesFound: 0)
    private(set) var rulesError: String?
    private(set) var ruleCount = 0

    private(set) var threats: [Threat] = []
    var selectedThreats: Set<String> = []
    private(set) var privacyItems: [PrivacyItem] = []
    var selectedPrivacy: Set<String> = []
    private(set) var extensions: [BrowserExtension] = []
    private(set) var wifiInterface: String?
    private(set) var wifiNetworks: [String] = []
    private(set) var permissions: [AppPermission] = []
    private(set) var permissionsUnreadable = false
    private(set) var lastReport: RemovalReport?
    private(set) var message: String?

    @ObservationIgnored unowned let app: AppModel
    @ObservationIgnored private var rules: YaraRules?
    @ObservationIgnored private var task: Task<Void, Never>?

    init(app: AppModel) {
        self.app = app
    }

    /// Opens a section, scanning first if needed (used by My Tools).
    func open(_ section: Section) {
        self.section = section
        if phase == .idle { scan() }
    }

    /// Compiles Apple's XProtect rules once (about a second) and keeps them.
    func loadRules() async -> YaraRules? {
        if let rules { return rules }
        do {
            let compiled = try await Task.detached(priority: .userInitiated) { try YaraRules.xprotect() }.value
            rules = compiled
            ruleCount = compiled.ruleCount
            return compiled
        } catch {
            rulesError = String(describing: error)
            return nil
        }
    }

    /// Fast pass used by Smart Care: persistence and the most exposed files.
    func quickThreatScan() async -> [Threat] {
        let rules = await loadRules()
        let home = app.safetyGuard.home
        let found = await Task.detached(priority: .userInitiated) {
            await ThreatScanner(home: home).scan(depth: .quick, rules: rules)
        }.value
        threats = found
        selectedThreats = Set(found.filter(\.isMalware).map(\.id))
        return found
    }

    func scan() {
        task?.cancel()
        phase = .scanning
        message = nil
        let onProgress: @Sendable (ScanProgress) -> Void = { [weak self] progress in
            Task { @MainActor in self?.progress = progress }
        }
        progress = ScanProgress(currentPath: String(localized: "Loading Apple's malware signatures…"), bytesFound: 0)
        task = Task {
            let rules = await loadRules()
            let home = app.safetyGuard.home
            let depth: ThreatScanner.Depth = deepScan ? .deep : .quick
            let found = await Task.detached(priority: .userInitiated) {
                await ThreatScanner(home: home).scan(depth: depth, rules: rules, progress: onProgress)
            }.value
            guard !Task.isCancelled else { return }
            threats = found
            selectedThreats = Set(found.filter(\.isMalware).map(\.id))

            progress = ScanProgress(currentPath: String(localized: "Checking browsers, Wi-Fi and permissions…"), bytesFound: 0, fraction: 1)
            let (privacy, extensions) = await Task.detached {
                let scanner = PrivacyScanner(home: home)
                return (scanner.scan(), scanner.extensions())
            }.value
            privacyItems = privacy
            self.extensions = extensions
            selectedPrivacy = Set(privacy.filter { $0.kind != .autofill }.map(\.id))
            loadWiFi()
            loadPermissions()
            phase = .ready
        }
    }

    func stop() {
        task?.cancel()
        phase = .idle
    }

    // MARK: Malware

    /// Removes the threat, the app bundle it lives in, and the launchd file that starts it.
    func removeThreats() {
        let chosen = threats.filter { selectedThreats.contains($0.id) }
        guard !chosen.isEmpty else { return }
        phase = .removing
        Task {
            var items: [CleanupItem] = []
            for threat in chosen {
                let target = Self.enclosingApp(of: threat.url) ?? threat.url
                items.append(CleanupItem(url: target, ruleID: "threat", size: FileSizes.allocatedSize(of: target).bytes))
                items += threat.related.map { CleanupItem(url: $0, ruleID: "threat", size: 0) }
                if !app.dryRun { await unload(threat) }
            }
            let report = await WorkspaceRemover.recycle(items, policy: .appRemoval, safetyGuard: app.safetyGuard, dryRun: app.dryRun)
            finish(report)
            if !report.wasSimulated {
                let failed = Set(report.failures.map(\.path))
                threats.removeAll { threat in chosen.contains(threat) && !failed.contains(threat.url.path(percentEncoded: false)) }
            }
            selectedThreats = []
        }
    }

    private func unload(_ threat: Threat) async {
        for plist in threat.related {
            let label = (NSDictionary(contentsOf: plist)?["Label"] as? String) ?? plist.deletingPathExtension().lastPathComponent
            if plist.path(percentEncoded: false).hasPrefix(app.safetyGuard.home.path(percentEncoded: false)) {
                let process = Process()
                process.executableURL = URL(filePath: "/bin/launchctl")
                process.arguments = ["bootout", "gui/\(getuid())", plist.path(percentEncoded: false)]
                try? process.run()
                process.waitUntilExit()
            } else {
                _ = await app.privileged.run(.bootout(label: label))
            }
        }
    }

    static func enclosingApp(of url: URL) -> URL? {
        var candidate = url
        while candidate.pathComponents.count > 1 {
            if candidate.pathExtension == "app" { return candidate }
            candidate.deleteLastPathComponent()
        }
        return nil
    }

    // MARK: Privacy

    func runningBrowser(for item: PrivacyItem) -> String? {
        guard let id = item.bundleID else { return nil }
        return app.runningApps()[id]
    }

    func cleanPrivacy() {
        let chosen = privacyItems.filter { selectedPrivacy.contains($0.id) }
        let blocked = chosen.compactMap(runningBrowser(for:))
        let ready = chosen.filter { runningBrowser(for: $0) == nil }
        guard !ready.isEmpty else {
            message = blocked.isEmpty ? nil : String(localized: "Quit \(Set(blocked).sorted().joined(separator: ", ")) first.")
            return
        }
        phase = .removing
        Task {
            let items = ready.flatMap { item in item.files.map { CleanupItem(url: $0, ruleID: "privacy", size: FileSizes.allocatedSize(of: $0).bytes) } }
            let report = await WorkspaceRemover.recycle(items, policy: .userInitiated, safetyGuard: app.safetyGuard, dryRun: app.dryRun)
            finish(report)
            if !report.wasSimulated {
                privacyItems.removeAll { ready.contains($0) }
            }
            selectedPrivacy.subtract(ready.map(\.id))
            message = blocked.isEmpty ? nil : String(localized: "Quit \(Set(blocked).sorted().joined(separator: ", ")) to clean its data.")
        }
    }

    func remove(_ ext: BrowserExtension) {
        Task {
            let item = CleanupItem(url: ext.folder, ruleID: "extension", size: FileSizes.allocatedSize(of: ext.folder).bytes)
            let report = await WorkspaceRemover.recycle([item], policy: .userInitiated, safetyGuard: app.safetyGuard, dryRun: app.dryRun)
            finish(report)
            if !report.wasSimulated, report.failures.isEmpty { extensions.removeAll { $0 == ext } }
        }
    }

    // MARK: Wi-Fi

    func loadWiFi() {
        Task {
            let (interface, networks) = await Task.detached { () -> (String?, [String]) in
                guard let interface = PrivacyScanner.wifiInterface() else { return (nil, []) }
                return (interface, PrivacyScanner.savedWiFiNetworks(interface: interface))
            }.value
            wifiInterface = interface
            wifiNetworks = networks
        }
    }

    func forget(_ network: String) {
        guard let interface = wifiInterface else { return }
        Task {
            if app.dryRun {
                message = String(localized: "Simulation: \(network) would be forgotten.")
                return
            }
            let result = await app.privileged.run(.forgetWiFiNetwork(name: network, interface: interface))
            if result.succeeded { wifiNetworks.removeAll { $0 == network } } else { message = result.output }
        }
    }

    // MARK: Permissions

    func loadPermissions() {
        let home = app.safetyGuard.home
        Task {
            do {
                permissions = try await Task.detached { try PermissionsReader.read(home: home) }.value
                permissionsUnreadable = false
            } catch {
                permissions = []
                permissionsUnreadable = true
            }
        }
    }

    func reset(_ permission: AppPermission) {
        guard !app.dryRun else {
            message = String(localized: "Simulation: the permission would be reset.")
            return
        }
        Task {
            let ok = await Task.detached { PermissionsReader.reset(permission) }.value
            if ok { permissions.removeAll { $0 == permission } } else { message = String(localized: "macOS refused to reset this permission.") }
        }
    }

    private func finish(_ report: RemovalReport) {
        lastReport = report
        app.record(report, module: .protection)
        phase = .ready
    }
}

/// Display data for TCC services.
enum PermissionService {
    static func title(_ shortName: String) -> String {
        switch shortName {
        case "Camera": String(localized: "Camera")
        case "Microphone": String(localized: "Microphone")
        case "ScreenCapture": String(localized: "Screen Recording")
        case "Accessibility": String(localized: "Accessibility")
        case "SystemPolicyAllFiles": String(localized: "Full Disk Access")
        case "ListenEvent": String(localized: "Input Monitoring")
        case "PostEvent": String(localized: "Keyboard and Mouse Control")
        case "AppleEvents": String(localized: "Automation")
        case "AddressBook": String(localized: "Contacts")
        case "Calendar": String(localized: "Calendars")
        case "Reminders": String(localized: "Reminders")
        case "Photos", "PhotosAdd": String(localized: "Photos")
        case "SystemPolicyDesktopFolder": String(localized: "Desktop Folder")
        case "SystemPolicyDocumentsFolder": String(localized: "Documents Folder")
        case "SystemPolicyDownloadsFolder": String(localized: "Downloads Folder")
        case "SystemPolicyRemovableVolumes": String(localized: "Removable Volumes")
        case "SystemPolicyNetworkVolumes": String(localized: "Network Volumes")
        case "BluetoothAlways": String(localized: "Bluetooth")
        case "MediaLibrary": String(localized: "Media & Apple Music")
        case "SpeechRecognition": String(localized: "Speech Recognition")
        case "DeveloperTool": String(localized: "Developer Tools")
        default: shortName
        }
    }

    static func symbol(_ shortName: String) -> String {
        switch shortName {
        case "Camera": "camera.fill"
        case "Microphone": "mic.fill"
        case "ScreenCapture": "rectangle.dashed.badge.record"
        case "Accessibility": "accessibility"
        case "SystemPolicyAllFiles": "internaldrive.fill"
        case "ListenEvent", "PostEvent": "keyboard.fill"
        case "AppleEvents": "gearshape.2.fill"
        case "AddressBook": "person.crop.circle.fill"
        case "Calendar": "calendar"
        case "Reminders": "checklist"
        case "Photos", "PhotosAdd": "photo.fill"
        case "BluetoothAlways": "dot.radiowaves.left.and.right"
        default: "lock.fill"
        }
    }

    /// Services that matter most for privacy come first.
    static let order = ["Camera", "Microphone", "ScreenCapture", "SystemPolicyAllFiles", "Accessibility", "ListenEvent", "AppleEvents"]
}
