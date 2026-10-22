import Foundation
import Testing
@testable import ReviveKit

@Suite struct RuleCatalogTests {
    @Test func bundledRulesLoadAndAreUnique() throws {
        let rules = try RuleCatalog.bundled()
        #expect(rules.count >= 10)
        #expect(Set(rules.map(\.id)).count == rules.count)
        #expect(Set(rules.map(\.category)) == Set(CleanupCategory.allCases))
        for rule in rules {
            #expect(!rule.paths.isEmpty, "\(rule.id) has no paths")
            #expect(rule.title.fr != nil && rule.detail.fr != nil, "\(rule.id) is missing a French translation")
        }
    }

    @Test func onlyTrashRulesDeletePermanently() throws {
        for rule in try RuleCatalog.bundled() where rule.removal == .permanent {
            #expect(rule.category == .trashBins)
            #expect(rule.paths.allSatisfy { $0.contains("/.Trash") })
        }
    }

    @Test func everyBundledRuleOnlyReachesAllowedLocations() throws {
        // Feed each rule's literal paths (globs replaced by a sample name) to the guard.
        let home = URL(filePath: "/Users/tester")
        let safety = SafetyGuard(home: home)
        for rule in try RuleCatalog.bundled() {
            for glob in rule.paths {
                let sample = glob.replacingOccurrences(of: "*", with: "sample").replacingOccurrences(of: "{uid}", with: "501")
                let url = URL(filePath: sample.expandingTilde(home: home))
                #expect(safety.check(url, policy: .automatic).isAllowed, "\(rule.id): \(glob)")
            }
        }
    }
}

@Suite struct PathPatternTests {
    @Test func expandsGlobsPerComponent() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.file("Library/Application Support/Google/Chrome/Default/Cache/data_0")
        try fixture.file("Library/Application Support/Google/Chrome/Profile 1/Cache/data_0")
        try fixture.file("Library/Application Support/Google/Chrome/Profile 1/History")

        let pattern = PathPattern(home: fixture.home)
        let matches = pattern.matches("~/Library/Application Support/Google/Chrome/*/Cache").map(\.lastPathComponent)
        #expect(matches == ["Cache", "Cache"])
        #expect(pattern.matches("~/Library/Nothing/*").isEmpty)
    }

    @Test func excludesMatchingPathsAndTheirChildren() throws {
        let pattern = PathPattern(home: URL(filePath: "/Users/tester"))
        let excludes = ["~/Library/Caches/JetBrains*"]
        #expect(pattern.isExcluded(URL(filePath: "/Users/tester/Library/Caches/JetBrains2025"), by: excludes))
        #expect(pattern.isExcluded(URL(filePath: "/Users/tester/Library/Caches/JetBrains/x/y"), by: excludes))
        #expect(!pattern.isExcluded(URL(filePath: "/Users/tester/Library/Caches/com.spotify.client"), by: excludes))
    }
}

@Suite struct CleanupScannerTests {
    @Test func findsJunkAndRespectsSafety() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.file("Library/Caches/com.spotify.client/Data/blob", size: 200_000)
        try fixture.file("Library/Caches/pip/http/wheel", size: 100_000)
        try fixture.file("Library/Caches/CloudKit/db", size: 100_000)
        try fixture.file("Library/Caches/JetBrains/index", size: 100_000)
        try fixture.file("Library/Logs/app.log")
        try fixture.file("Documents/thesis.pages")
        try fixture.file(".Trash/old.zip")

        let scanner = CleanupScanner(rules: try RuleCatalog.bundled(), safetyGuard: fixture.safetyGuard)
        let result = try await scanner.scan()
        let paths = Set(result.allItems.map { $0.url.lastPathComponent })

        #expect(paths.contains("com.spotify.client"))
        #expect(paths.contains("app.log"))
        #expect(paths.contains("old.zip"))
        #expect(!paths.contains("CloudKit"), "hard-protected cache")
        #expect(!paths.contains("JetBrains"), "excluded by rule")
        #expect(!paths.contains("thesis.pages"))

        // pip is claimed by the AI rule, not counted twice under user caches.
        let pip = result.allItems.filter { $0.url.lastPathComponent == "pip" }
        #expect(pip.count == 1)
        #expect(pip.first?.ruleID == "ai-python-caches")
        #expect(result.totalSize(in: .systemJunk) >= 200_000)
        #expect(result.results.first { $0.rule.id == "user-trash" }?.items.first?.removal == .permanent)
    }

    @Test func itemsOfRunningAppsStartUnchecked() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.file("Library/Caches/com.anthropic.claudefordesktop/blob")
        try fixture.file("Library/Caches/com.spotify.client/blob")

        let scanner = CleanupScanner(
            rules: try RuleCatalog.bundled(), safetyGuard: fixture.safetyGuard,
            runningApps: ["com.anthropic.claudefordesktop": "Claude"]
        )
        let result = try await scanner.scan()
        let claude = try #require(result.allItems.first { $0.url.lastPathComponent == "com.anthropic.claudefordesktop" })
        #expect(claude.usedByRunningApp == "Claude")
        #expect(!result.defaultSelection.contains(claude.id))
        #expect(result.defaultSelection.count == 1)
    }

    @Test func onlyScansRequestedCategories() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.file("Library/Caches/com.spotify.client/blob")
        try fixture.file(".Trash/old.zip")

        let scanner = CleanupScanner(rules: try RuleCatalog.bundled(), safetyGuard: fixture.safetyGuard)
        let result = try await scanner.scan(categories: [.trashBins])
        #expect(result.results.map(\.rule.category) == [.trashBins])
    }
}

@Suite struct RemoverTests {
    @Test func dryRunTouchesNothing() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let file = try fixture.file("Library/Caches/com.example/blob")
        let item = CleanupItem(url: file.deletingLastPathComponent(), ruleID: "user-caches", size: 50_000)

        let report = await Remover(safetyGuard: fixture.safetyGuard, dryRun: true).remove([item], policy: .automatic)
        #expect(report.wasSimulated)
        #expect(report.removedCount == 1)
        #expect(report.freedBytes == 50_000)
        #expect(fixture.exists("Library/Caches/com.example/blob"))
    }

    @Test func refusesBlockedItemsEvenIfAsked() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let doc = try fixture.file("Documents/keep.txt")
        let item = CleanupItem(url: doc, ruleID: "bogus", size: 10)

        let report = await Remover(safetyGuard: fixture.safetyGuard, dryRun: false).remove([item], policy: .automatic)
        #expect(report.removedCount == 0)
        #expect(report.failures.count == 1)
        #expect(fixture.exists("Documents/keep.txt"))
    }

    @Test func permanentDeletionOnlyInsideTrash() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let trashed = try fixture.file(".Trash/old.zip")
        let cache = try fixture.file("Library/Caches/com.example/blob")
        let items = [
            CleanupItem(url: trashed, ruleID: "user-trash", size: 1, removal: .permanent),
            CleanupItem(url: cache, ruleID: "bogus", size: 1, removal: .permanent),
        ]

        let report = await Remover(safetyGuard: fixture.safetyGuard, dryRun: false).remove(items, policy: .automatic)
        #expect(report.removedCount == 1)
        #expect(!fixture.exists(".Trash/old.zip"))
        #expect(fixture.exists("Library/Caches/com.example/blob"))
    }
}

@Suite struct ActivityLogTests {
    @Test func persistsEntriesNewestFirst() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let file = fixture.home.appending(path: "activity.json")
        let log = ActivityLog(fileURL: file)
        try await log.append(ActivityEntry(module: "cleanup", freedBytes: 10, itemCount: 1, failureCount: 0, wasSimulated: false))
        try await log.append(ActivityEntry(module: "spaceLens", freedBytes: 20, itemCount: 2, failureCount: 0, wasSimulated: true))

        let reloaded = await ActivityLog(fileURL: file).entries()
        #expect(reloaded.map(\.module) == ["spaceLens", "cleanup"])
    }
}

/// Moves a real file to the user's Trash; opt-in because it leaves the probe file there.
/// Run with `REVIVE_TRASH_TEST=1 swift test --filter realTrash`.
@Suite struct RealTrashTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["REVIVE_TRASH_TEST"] == "1"))
    func realTrashMovesItemToTheTrash() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let name = "ReviveTrashProbe-\(UUID().uuidString.prefix(8))"
        let file = try fixture.file("Library/Caches/\(name)/probe.bin")

        let item = CleanupItem(url: file.deletingLastPathComponent(), ruleID: "user-caches", size: 50_000)
        let report = await Remover(safetyGuard: fixture.safetyGuard, dryRun: false).remove([item], policy: .automatic)

        #expect(report.removedCount == 1)
        #expect(!fixture.exists("Library/Caches/\(name)"))
        let trash = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".Trash/\(name)")
        let inTrash = FileManager.default.fileExists(atPath: trash.path(percentEncoded: false))
        let trashListable = (try? FileManager.default.contentsOfDirectory(atPath: trash.deletingLastPathComponent().path(percentEncoded: false))) != nil
        // Without Full Disk Access ~/.Trash cannot be listed; only check when it can.
        if trashListable { #expect(inTrash) }
        print("Probe sent to the Trash as \(name); visible in Trash: \(inTrash)")
    }
}

/// Same as RealTrashTests, through NSWorkspace (used for apps and user files).
@Suite struct RealWorkspaceTrashTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["REVIVE_TRASH_TEST"] == "1"))
    @MainActor
    func workspaceRecycleMovesItemToTheTrash() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let file = try fixture.file("Documents/ReviveWorkspaceProbe-\(UUID().uuidString.prefix(8)).txt", size: 1000)
        let item = CleanupItem(url: file, ruleID: "probe", size: 1000)

        let blocked = await WorkspaceRemover.recycle([item], policy: .automatic, safetyGuard: fixture.safetyGuard, dryRun: false)
        #expect(blocked.removedCount == 0 && blocked.failures.count == 1, "documents are off-limits for automatic cleanups")

        let report = await WorkspaceRemover.recycle([item], policy: .userInitiated, safetyGuard: fixture.safetyGuard, dryRun: false)
        #expect(report.removedCount == 1)
        #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
        print("Workspace probe sent to the Trash: \(file.lastPathComponent)")
    }
}

@Suite struct UnattendedScanTests {
    @Test func skipsPromptingLocationsWhenAsked() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.file("Library/Containers/com.apple.mail/Data/Library/Mail Downloads/A/file.pdf")
        try fixture.file("Library/Caches/com.spotify.client/blob")

        var scanner = CleanupScanner(rules: try RuleCatalog.bundled(), safetyGuard: fixture.safetyGuard)
        scanner.avoidsPrivacyPrompts = true
        let names = try await scanner.scan().allItems.map { $0.url.lastPathComponent }
        #expect(names == ["com.spotify.client"])
    }
}
