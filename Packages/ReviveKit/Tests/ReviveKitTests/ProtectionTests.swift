import Foundation
import Testing
@testable import ReviveKit

@Suite struct YaraTests {
    @Test func compilesAndMatchesCustomRules() throws {
        let rules = try YaraRules(sources: [("test", """
        rule ReviveTestMarker { strings: $a = "REVIVE-TEST-MARKER-0042" condition: $a }
        rule NeverMatches { strings: $b = "this string is not in the file" condition: $b }
        """)])
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let infected = fixture.home.appending(path: "infected.bin")
        try Data("header REVIVE-TEST-MARKER-0042 footer".utf8).write(to: infected)
        let clean = try fixture.file("clean.bin", size: 1000)

        #expect(rules.scan(infected) == ["ReviveTestMarker"])
        #expect(rules.scan(clean).isEmpty)
    }

    @Test func reportsCompilationErrors() {
        #expect(throws: YaraRules.Failure.self) {
            _ = try YaraRules(sources: [("bad", "rule Broken { condition: $missing }")])
        }
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: YaraRules.xprotectFolder.appending(path: "XProtect.yara").path(percentEncoded: false))))
    func compilesApplesXProtectRules() throws {
        let rules = try YaraRules.xprotect()
        #expect(rules.ruleCount > 100)
        // A plain system binary must not match any malware signature.
        #expect(rules.scan(URL(filePath: "/bin/ls")).isEmpty)
    }
}

@Suite struct ThreatScannerTests {
    @Test func flagsPersistenceInTemporaryFolders() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let program = try fixture.file("bin/payload", size: 100)
        let shared = URL(filePath: "/tmp/revive-test-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: program, to: shared)
        defer { try? FileManager.default.removeItem(at: shared) }

        let items = [
            LaunchItem(label: "evil", plist: fixture.home.appending(path: "Library/LaunchAgents/evil.plist"), scope: .userAgent,
                       program: shared.path(percentEncoded: false), runsAtLoad: true, keepsAlive: true, isDisabled: false),
            LaunchItem(label: "ok", plist: fixture.home.appending(path: "Library/LaunchAgents/ok.plist"), scope: .userAgent,
                       program: "/bin/ls", runsAtLoad: true, keepsAlive: false, isDisabled: false),
        ]
        let findings = ThreatScanner(home: fixture.home).persistenceFindings(items)
        #expect(findings.count == 1)
        #expect(findings.first?.related.first?.lastPathComponent == "evil.plist")
    }

    @Test func detectsExecutableFormats() throws {
        #expect(ThreatScanner.isMachO(URL(filePath: "/bin/ls")))
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let script = fixture.home.appending(path: "run")
        try Data("#!/bin/sh\necho hi\n".utf8).write(to: script)
        #expect(ThreatScanner.hasShebang(script))
        #expect(!ThreatScanner.isMachO(script))
    }
}

@Suite struct PrivacyTests {
    @Test func findsBrowserTracesButNeverPasswords() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let profile = "Library/Application Support/Google/Chrome/Default"
        try fixture.file("\(profile)/History")
        try fixture.file("\(profile)/Cookies")
        try fixture.file("\(profile)/Login Data")
        try fixture.file("\(profile)/Bookmarks")
        try fixture.file("\(profile)/Extensions/abcdef/1.0/manifest.json", size: 1)
        try Data(#"{"name": "__MSG_name__", "version": "1.0", "default_locale": "en"}"#.utf8)
            .write(to: fixture.home.appending(path: "\(profile)/Extensions/abcdef/1.0/manifest.json"))
        try fixture.file("\(profile)/Extensions/abcdef/1.0/_locales/en/messages.json", size: 1)
        try Data(#"{"name": {"message": "Ad Blocker"}}"#.utf8)
            .write(to: fixture.home.appending(path: "\(profile)/Extensions/abcdef/1.0/_locales/en/messages.json"))

        let scanner = PrivacyScanner(home: fixture.home)
        let items = scanner.scan()
        let files = Set(items.flatMap(\.files).map(\.lastPathComponent))
        #expect(files.contains("History"))
        #expect(files.contains("Cookies"))
        #expect(!files.contains("Login Data"))
        #expect(!files.contains("Bookmarks"))
        #expect(items.allSatisfy { $0.bundleID == "com.google.Chrome" })
        #expect(scanner.extensions().map(\.name) == ["Ad Blocker"])
    }
}

@Suite struct ClutterTests {
    @Test func findsDuplicatesAndKeepsTheOldest() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let original = try fixture.file("Documents/report.pdf", size: 300_000)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000)], ofItemAtPath: original.path(percentEncoded: false))
        for folder in ["Downloads", "Desktop"] {
            try FileManager.default.createDirectory(at: fixture.home.appending(path: folder), withIntermediateDirectories: true)
        }
        try FileManager.default.copyItem(at: original, to: fixture.home.appending(path: "Downloads/report (1).pdf"))
        try FileManager.default.copyItem(at: original, to: fixture.home.appending(path: "Desktop/report copy.pdf"))
        try fixture.file("Documents/other.pdf", size: 300_000 + 4096)
        // Same size, different content: not a duplicate.
        let different = fixture.home.appending(path: "Documents/same-size.bin")
        try Data(repeating: 0x01, count: 300_000).write(to: different)

        let result = await ClutterScanner(home: fixture.home).scan()
        #expect(result.duplicates.count == 1)
        let group = try #require(result.duplicates.first)
        #expect(group.files.count == 3)
        #expect(group.files.first?.url.lastPathComponent == "report.pdf")
    }

    @Test func findsLargeFilesAndScreenshots() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.file("Movies/big.mov", size: 60_000_000)
        try fixture.file("Desktop/Screenshot 2026-01-01 at 10.00.00.png", size: 1000)
        try fixture.file("Desktop/notes.txt", size: 1000)

        let result = await ClutterScanner(home: fixture.home).scan()
        #expect(result.largeOldFiles.map(\.url.lastPathComponent) == ["big.mov"])
        #expect(result.screenshots.map(\.url.lastPathComponent) == ["Screenshot 2026-01-01 at 10.00.00.png"])
    }

    @Test func skipsPackagesLikePhotosLibraries() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.file("Pictures/Photos Library.photoslibrary/originals/a.heic", size: 60_000_000)
        let result = await ClutterScanner(home: fixture.home).scan()
        #expect(result.largeOldFiles.isEmpty)
    }
}

@Suite struct CloudTests {
    @Test func namesProviders() {
        #expect(CloudScanner.providerName("GoogleDrive-me@gmail.com") == "Google Drive")
        #expect(CloudScanner.providerName("OneDrive-Personal") == "OneDrive")
    }

    @Test func findsLocalCopiesOfCloudFiles() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.file("Library/CloudStorage/GoogleDrive-me/My Drive/video.mp4", size: 2_000_000)
        try fixture.file("Downloads/video.mp4", size: 2_000_000)
        try fixture.file("Downloads/unrelated.mp4", size: 2_000_000 + 4096)

        let result = CloudScanner(home: fixture.home).scan()
        #expect(result.providers.map(\.name) == ["Google Drive"])
        #expect(result.localDuplicates.map(\.url.lastPathComponent) == ["video.mp4"])
    }
}
