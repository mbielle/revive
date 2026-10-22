import AppKit
import Foundation

/// Removes items the user picked with Finder-like behavior: authentication is requested by macOS
/// when an item belongs to the system (e.g. App Store apps), and everything lands in the Trash.
public enum WorkspaceRemover {
    @MainActor
    public static func recycle(_ items: [CleanupItem], policy: SafetyGuard.Policy, safetyGuard: SafetyGuard, dryRun: Bool) async -> RemovalReport {
        var report = RemovalReport()
        report.wasSimulated = dryRun
        var allowed: [CleanupItem] = []
        for item in items {
            if case let .blocked(reason) = safetyGuard.check(item.url, policy: policy) {
                report.failures.append(.init(path: item.url.path(percentEncoded: false), reason: reason))
            } else {
                allowed.append(item)
            }
        }
        guard !allowed.isEmpty else { return report }
        if dryRun {
            report.removedCount = allowed.count
            report.freedBytes = allowed.reduce(0) { $0 + $1.size }
            return report
        }
        for item in allowed {
            do {
                _ = try await NSWorkspace.shared.recycle([item.url])
                report.removedCount += 1
                report.freedBytes += item.size
            } catch {
                report.failures.append(.init(path: item.url.path(percentEncoded: false), reason: error.localizedDescription))
            }
        }
        return report
    }
}
