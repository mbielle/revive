import Foundation
import Testing
@testable import ReviveKit

@Suite struct SpaceScannerTests {
    @Test func measuresTreeAndFoldsSmallItems() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.file("Movies/big.mov", size: 3_000_000)
        try fixture.file("Movies/clips/a.mov", size: 2_000_000)
        try fixture.file("Documents/note.txt", size: 100)

        var scanner = SpaceScanner()
        scanner.minimumListedSize = 1_000_000
        let root = try await scanner.scan(fixture.home)

        let movies = try #require(root.children.first { $0.name == "Movies" })
        #expect(movies.size >= 5_000_000)
        #expect(movies.children.map(\.name) == ["big.mov", "clips"])
        // Documents is below the listing threshold: folded into "other".
        #expect(!root.children.contains { $0.name == "Documents" })
        #expect(root.otherSize > 0)
        #expect(root.size == root.children.reduce(root.otherSize) { $0 + $1.size })
    }

    @Test func removingUpdatesAncestorSizes() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let big = try fixture.file("Movies/big.mov", size: 3_000_000)
        try fixture.file("Movies/keep.mov", size: 2_000_000)

        let root = try await SpaceScanner().scan(fixture.home)
        let pruned = root.removing([big.path(percentEncoded: false)])
        let movies = try #require(pruned.children.first { $0.name == "Movies" })
        #expect(movies.children.map(\.name) == ["keep.mov"])
        #expect(pruned.size < root.size)
        #expect(pruned.node(withID: big.path(percentEncoded: false)) == nil)
    }
}
