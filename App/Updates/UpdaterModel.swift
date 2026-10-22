import Sparkle
import SwiftUI

/// Revive's own updates, through Sparkle: checks the feed at launch and every hour, shows
/// Sparkle's update window, installs and relaunches when the user agrees.
@MainActor @Observable
final class UpdaterModel {
    private(set) var canCheckForUpdates = false

    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue; revision += 1 }
    }

    var automaticallyDownloads: Bool {
        get { controller.updater.automaticallyDownloadsUpdates }
        set { controller.updater.automaticallyDownloadsUpdates = newValue; revision += 1 }
    }

    var lastCheck: Date? { _ = revision; return controller.updater.lastUpdateCheckDate }

    /// Bumped so views re-read Sparkle's own settings after a change.
    private var revision = 0

    @ObservationIgnored private let delegate = FeedDelegate()
    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: delegate, userDriverDelegate: nil)
        // Sparkle changes this property on the main thread.
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
        #if DEBUG
        // `-checkForUpdatesNow YES` checks right away (with the window), `-checkInBackground YES` silently.
        if UserDefaults.standard.bool(forKey: "checkForUpdatesNow") {
            Task { @MainActor in self.checkForUpdates() }
        } else if UserDefaults.standard.bool(forKey: "checkInBackground") {
            Task { @MainActor in self.controller.updater.checkForUpdatesInBackground() }
        }
        #endif
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    var currentVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

/// Debug builds can point at another feed (`-updateFeedURL <url>`) to test an update locally.
private final class FeedDelegate: NSObject, SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "updateFeedURL")
        #else
        return nil
        #endif
    }
}
