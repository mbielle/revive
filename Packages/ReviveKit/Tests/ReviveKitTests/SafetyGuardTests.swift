import Foundation
import Testing
@testable import ReviveKit

@Suite struct SafetyGuardTests {
    let home = URL(filePath: "/Users/tester")
    var safety: SafetyGuard { SafetyGuard(home: home) }

    private func url(_ path: String) -> URL {
        URL(filePath: path.expandingTilde(home: home))
    }

    @Test(arguments: [
        "/", "/System/Library/Caches/x", "/usr/lib/libz.dylib", "/Applications/Safari.app", "/Library/Caches/x",
        "/private/var/db/x", "/Users/someoneelse/Library/Caches/x",
        "~", "~/Documents", "~/Library", "~/Library/Caches", "~/Library/Application Support",
        "~/Library/Keychains/login.keychain-db", "~/Library/Mobile Documents/com~apple~CloudDocs/file.txt",
        "~/Library/CloudStorage/GoogleDrive/file", "~/Library/Mail/V10/x", "~/.ssh/id_ed25519",
        "~/Library/Caches/CloudKit", "~/Library/Caches/com.apple.FontRegistry", "~/Library/Caches/com.apple.Spotlight/x",
        "~/Pictures/Photos Library.photoslibrary/database/Photos.sqlite",
        "/Volumes/Backup/Projects/file", "/Volumes/Backup", "~/Library/Caches/../Keychains/x",
    ])
    func blocksUnderAnyPolicy(_ path: String) {
        #expect(!safety.check(url(path), policy: .automatic).isAllowed, "\(path) should be blocked")
        #expect(!safety.check(url(path), policy: .userInitiated).isAllowed, "\(path) should be blocked")
    }

    @Test(arguments: [
        "~/Library/Caches/com.spotify.client", "~/Library/Logs/DiagnosticReports/a.ips",
        "~/Library/Developer/Xcode/DerivedData/App-abc", "~/.Trash/old.zip", "~/.cache/huggingface/hub/models--x",
        "~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads/ABC", "/Volumes/Backup/.Trashes/501/file",
    ])
    func allowsJunkLocations(_ path: String) {
        #expect(safety.check(url(path), policy: .automatic).isAllowed, "\(path) should be allowed")
    }

    @Test func userContentOnlyWhenUserPicksIt() {
        let doc = url("~/Documents/Old Project/video.mov")
        #expect(!safety.check(doc, policy: .automatic).isAllowed)
        #expect(safety.check(doc, policy: .userInitiated).isAllowed)
        // The Photos library as a whole can be removed by the user, never its insides.
        #expect(safety.check(url("~/Pictures/Old.photoslibrary"), policy: .userInitiated).isAllowed)
    }

    @Test func honorsUserExclusions() {
        var safety = safety
        safety.userExclusions = [url("~/Library/Caches/com.important.app")]
        #expect(!safety.check(url("~/Library/Caches/com.important.app/data"), policy: .automatic).isAllowed)
        #expect(safety.check(url("~/Library/Caches/com.other.app"), policy: .automatic).isAllowed)
    }

    @Test func followsSymlinkedParents() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        // ~/Library/Caches/evil → /System/Library : anything below it must be refused.
        try FileManager.default.createDirectory(at: fixture.home.appending(path: "Library/Caches"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: fixture.home.appending(path: "Library/Caches/evil"), withDestinationURL: URL(filePath: "/System/Library")
        )
        let target = fixture.home.appending(path: "Library/Caches/evil/CoreServices")
        #expect(!fixture.safetyGuard.check(target, policy: .automatic).isAllowed)
        // The link itself can go: trashing a symlink never touches its destination.
        #expect(fixture.safetyGuard.check(fixture.home.appending(path: "Library/Caches/evil"), policy: .automatic).isAllowed)
    }
}
