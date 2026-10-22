import Foundation

/// Outcome of a removal run.
public struct RemovalReport: Sendable {
    public struct Failure: Sendable, Identifiable {
        public var id: String { path }
        public let path: String
        public let reason: String

        public init(path: String, reason: String) {
            self.path = path
            self.reason = reason
        }
    }

    public var freedBytes: Int64 = 0
    public var removedCount = 0
    public var failures: [Failure] = []
    public var wasSimulated = false

    public init() {}
}

/// Moves items to the Trash (or deletes items that already are in a Trash).
/// Every item is re-checked by the `SafetyGuard` right before it is touched.
public struct Remover: Sendable {
    public let safetyGuard: SafetyGuard
    /// Simulation mode: report what would happen without touching the disk.
    public let dryRun: Bool

    public init(safetyGuard: SafetyGuard, dryRun: Bool) {
        self.safetyGuard = safetyGuard
        self.dryRun = dryRun
    }

    public func remove(
        _ items: [CleanupItem],
        policy: SafetyGuard.Policy,
        progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }
    ) async -> RemovalReport {
        var report = RemovalReport()
        report.wasSimulated = dryRun

        for (index, item) in items.enumerated() {
            if Task.isCancelled { break }
            let path = item.url.path(percentEncoded: false)
            progress(ScanProgress(currentPath: path, bytesFound: report.freedBytes,
                                  fraction: Double(index) / Double(max(items.count, 1))))

            if case let .blocked(reason) = safetyGuard.check(item.url, policy: policy) {
                report.failures.append(.init(path: path, reason: reason))
                continue
            }
            // Permanent deletion is reserved for content that already sits in a Trash folder.
            if item.removal == .permanent, !Self.isInTrash(item.url) {
                report.failures.append(.init(path: path, reason: "Not in a Trash folder"))
                continue
            }

            do {
                if !dryRun {
                    switch item.removal {
                    case .trash: try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                    case .permanent: try FileManager.default.removeItem(at: item.url)
                    }
                }
                report.freedBytes += item.size
                report.removedCount += 1
            } catch {
                report.failures.append(.init(path: path, reason: error.localizedDescription))
            }
        }
        progress(ScanProgress(currentPath: "", bytesFound: report.freedBytes, fraction: 1))
        return report
    }

    static func isInTrash(_ url: URL) -> Bool {
        let parts = url.normalizedPath.split(separator: "/")
        return parts.contains(".Trash") || parts.contains(".Trashes")
    }
}
