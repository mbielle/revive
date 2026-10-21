import Foundation

/// Live status sent by a scanner while it works.
public struct ScanProgress: Sendable {
    public var currentPath: String
    public var bytesFound: Int64
    /// 0...1 when the total amount of work is known.
    public var fraction: Double?
    /// Number of entries looked at so far, for scanners that count files.
    public var itemCount: Int

    public init(currentPath: String, bytesFound: Int64, fraction: Double? = nil, itemCount: Int = 0) {
        self.currentPath = currentPath
        self.bytesFound = bytesFound
        self.fraction = fraction
        self.itemCount = itemCount
    }
}

/// One file or folder a scanner proposes to remove.
public struct CleanupItem: Identifiable, Hashable, Sendable {
    public var id: String { url.normalizedPath }
    public let url: URL
    public let ruleID: String
    public let size: Int64
    /// False when some content could not be read (usually missing Full Disk Access).
    public let isSizeComplete: Bool
    /// Name of the running app that uses this item, if any. Such items start unchecked.
    public var usedByRunningApp: String?
    public let removal: CleanupRule.Removal

    public init(url: URL, ruleID: String, size: Int64, isSizeComplete: Bool = true,
                usedByRunningApp: String? = nil, removal: CleanupRule.Removal = .trash) {
        self.url = url
        self.ruleID = ruleID
        self.size = size
        self.isSizeComplete = isSizeComplete
        self.usedByRunningApp = usedByRunningApp
        self.removal = removal
    }

    public var displayName: String {
        FileManager.default.displayName(atPath: url.path(percentEncoded: false))
    }
}

/// Items found for one rule.
public struct RuleResult: Identifiable, Hashable, Sendable {
    public var id: String { rule.id }
    public let rule: CleanupRule
    public var items: [CleanupItem]

    public var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
}

/// Everything a cleanup scan found, grouped by rule.
public struct CleanupScanResult: Sendable {
    public var results: [RuleResult]
    /// Folders that could not be read at all; a hint that Full Disk Access is missing.
    public var unreadableLocations: [String]

    public init(results: [RuleResult] = [], unreadableLocations: [String] = []) {
        self.results = results
        self.unreadableLocations = unreadableLocations
    }

    public func results(in category: CleanupCategory) -> [RuleResult] {
        results.filter { $0.rule.category == category }
    }

    public func totalSize(in category: CleanupCategory) -> Int64 {
        results(in: category).reduce(0) { $0 + $1.totalSize }
    }

    public var totalSize: Int64 { results.reduce(0) { $0 + $1.totalSize } }

    public var allItems: [CleanupItem] { results.flatMap(\.items) }

    /// Size of the items checked by default: what a one-click cleanup removes.
    public var recommendedSize: Int64 {
        let ids = defaultSelection
        return allItems.filter { ids.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    /// Item ids that should be pre-checked in the review screen.
    public var defaultSelection: Set<String> {
        Set(results.filter(\.rule.selectedByDefault).flatMap(\.items).filter { $0.usedByRunningApp == nil }.map(\.id))
    }
}
