import Foundation

/// Finds removable items for a set of cleanup rules.
///
/// Scanning never modifies anything. It expands each rule's paths, drops what the
/// `SafetyGuard` refuses or another rule already claimed, then measures sizes in parallel.
public struct CleanupScanner: Sendable {
    public let rules: [CleanupRule]
    public let safetyGuard: SafetyGuard
    /// Bundle id → name of apps running when the scan starts.
    public let runningApps: [String: String]
    /// How many folders are measured at the same time.
    public var concurrency = 6
    /// Skip places where macOS would ask the user for permission (other apps' containers).
    /// Unattended scans set it when Full Disk Access is missing: the prompt would block the scan.
    public var avoidsPrivacyPrompts = false

    public init(rules: [CleanupRule], safetyGuard: SafetyGuard, runningApps: [String: String] = [:]) {
        self.rules = rules
        self.safetyGuard = safetyGuard
        self.runningApps = runningApps
    }

    private struct Candidate: Sendable {
        let ruleIndex: Int
        let url: URL
        let usedByRunningApp: String?
    }

    public func scan(
        categories: Set<CleanupCategory> = Set(CleanupCategory.allCases),
        progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }
    ) async throws -> CleanupScanResult {
        let (candidates, unreadable) = collectCandidates(categories: categories)
        var itemsByRule: [Int: [CleanupItem]] = [:]
        var bytesFound: Int64 = 0
        var done = 0

        try await withThrowingTaskGroup(of: (Int, CleanupItem?).self) { group in
            var iterator = candidates.makeIterator()
            func addNext() -> Bool {
                guard let candidate = iterator.next() else { return false }
                let removal = rules[candidate.ruleIndex].removal
                let ruleID = rules[candidate.ruleIndex].id
                group.addTask {
                    try Task.checkCancellation()
                    let (size, complete) = FileSizes.allocatedSize(of: candidate.url)
                    guard size > 0 else { return (candidate.ruleIndex, nil) }
                    return (candidate.ruleIndex, CleanupItem(
                        url: candidate.url, ruleID: ruleID, size: size, isSizeComplete: complete,
                        usedByRunningApp: candidate.usedByRunningApp, removal: removal
                    ))
                }
                return true
            }

            for _ in 0..<concurrency where addNext() {}
            while let (ruleIndex, item) = try await group.next() {
                done += 1
                if let item {
                    itemsByRule[ruleIndex, default: []].append(item)
                    bytesFound += item.size
                }
                progress(ScanProgress(
                    currentPath: item?.url.path(percentEncoded: false) ?? "",
                    bytesFound: bytesFound,
                    fraction: candidates.isEmpty ? 1 : Double(done) / Double(candidates.count)
                ))
                _ = addNext()
            }
        }

        let results = rules.indices.compactMap { index -> RuleResult? in
            guard let items = itemsByRule[index], !items.isEmpty else { return nil }
            return RuleResult(rule: rules[index], items: items.sorted { $0.size > $1.size })
        }
        return CleanupScanResult(results: results, unreadableLocations: unreadable)
    }

    private func collectCandidates(categories: Set<CleanupCategory>) -> ([Candidate], [String]) {
        let pattern = PathPattern(home: safetyGuard.home)
        var claimed: [String] = []
        var candidates: [Candidate] = []
        var unreadable: [String] = []

        for (index, rule) in rules.enumerated() where categories.contains(rule.category) {
            let runningApp = rule.appBundleIDs.lazy.compactMap { runningApps[$0] }.first
            for glob in rule.paths {
                noteUnreadableParent(of: glob, pattern: pattern, into: &unreadable)
                if avoidsPrivacyPrompts, Self.triggersPrivacyPrompt(pattern.expandedPattern(glob)) { continue }
                for url in pattern.matches(glob) {
                    if url.lastPathComponent == ".DS_Store" { continue }
                    if pattern.isExcluded(url, by: rule.exclude) { continue }
                    let path = url.normalizedPath
                    if claimed.contains(where: { path == $0 || path.hasPrefix($0 + "/") || $0.hasPrefix(path + "/") }) { continue }
                    guard safetyGuard.check(url, policy: .automatic).isAllowed else { continue }
                    if let minAge = rule.minAgeDays, !isOlder(url, thanDays: minAge) { continue }
                    claimed.append(path)
                    candidates.append(Candidate(ruleIndex: index, url: url, usedByRunningApp: runningApp))
                }
            }
        }
        return (candidates, unreadable)
    }

    /// Records the folder a glob lists from when it exists but cannot be read (privacy protection).
    private func noteUnreadableParent(of path: String, pattern: PathPattern, into list: inout [String]) {
        let expanded = pattern.expandedPattern(path)
        guard let globIndex = expanded.firstIndex(where: { "*?[".contains($0) }) else { return }
        let parent = (String(expanded[..<globIndex]) as NSString).deletingLastPathComponent
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent, isDirectory: &isDirectory), isDirectory.boolValue else { return }
        if (try? FileManager.default.contentsOfDirectory(atPath: parent)) == nil, !list.contains(parent) {
            list.append(parent)
        }
    }

    static func triggersPrivacyPrompt(_ path: String) -> Bool {
        ["/Library/Containers/", "/Library/Group Containers/", "/Library/Mail", "/Library/Safari", "/.Trash"].contains { path.contains($0) }
    }

    private func isOlder(_ url: URL, thanDays days: Int) -> Bool {
        guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
            return false
        }
        return date < Date.now.addingTimeInterval(-Double(days) * 86_400)
    }
}
