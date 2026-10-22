import Foundation
import ReviveKit
import ServiceManagement
import UserNotifications

/// Runs a silent junk scan on a schedule while Revive is open, and notifies when junk piles up.
/// Nothing is ever removed automatically.
@MainActor @Observable
final class AutoScanScheduler {
    enum Frequency: String, CaseIterable, Identifiable {
        case never, daily, weekly
        var id: String { rawValue }

        var interval: TimeInterval? {
            switch self {
            case .never: nil
            case .daily: 86_400
            case .weekly: 7 * 86_400
            }
        }
    }

    var frequency: Frequency {
        didSet {
            UserDefaults.standard.set(frequency.rawValue, forKey: "autoScanFrequency")
            reschedule()
            if frequency != .never { requestNotificationPermission() }
        }
    }

    /// Notify once junk reaches this many gigabytes.
    var thresholdGB: Int {
        didSet { UserDefaults.standard.set(thresholdGB, forKey: "autoScanThresholdGB") }
    }

    var opensAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            loginItemRevision += 1
        }
    }
    /// Bumped to refresh views after a login item change.
    private(set) var loginItemRevision = 0

    private(set) var lastRun: Date? {
        didSet { UserDefaults.standard.set(lastRun, forKey: "autoScanLastRun") }
    }

    @ObservationIgnored private var scheduler: NSBackgroundActivityScheduler?

    init() {
        frequency = Frequency(rawValue: UserDefaults.standard.string(forKey: "autoScanFrequency") ?? "") ?? .never
        thresholdGB = UserDefaults.standard.object(forKey: "autoScanThresholdGB") as? Int ?? 5
        lastRun = UserDefaults.standard.object(forKey: "autoScanLastRun") as? Date
        reschedule()
    }

    func reschedule() {
        scheduler?.invalidate()
        scheduler = nil
        guard let interval = frequency.interval else { return }
        let activity = NSBackgroundActivityScheduler(identifier: "io.github.mbielle.Revive.autoscan")
        activity.repeats = true
        activity.interval = interval
        activity.tolerance = interval / 10
        activity.qualityOfService = .utility
        activity.schedule { [weak self] completion in
            Task { @MainActor in
                await self?.runScan()
                completion(.finished)
            }
        }
        scheduler = activity
    }

    func runScan() async {
        var scanner = CleanupScanner(rules: (try? RuleCatalog.bundled()) ?? [], safetyGuard: SafetyGuard())
        // Nobody is there to answer a permission prompt during a background scan.
        scanner.avoidsPrivacyPrompts = !SystemStatus.hasFullDiskAccess()
        let configured = scanner
        guard let result = try? await Task.detached(priority: .utility, operation: { try await configured.scan() }).value else { return }
        lastRun = .now
        let junk = result.recommendedSize
        guard junk >= Int64(thresholdGB) * 1_000_000_000 else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Time for a cleanup")
        content.body = String(localized: "\(ByteCountFormatter.string(fromByteCount: junk, countStyle: .file)) of junk piled up on your Mac. Open Revive to review it.")
        content.sound = .default
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "autoscan", content: content, trigger: nil))
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
