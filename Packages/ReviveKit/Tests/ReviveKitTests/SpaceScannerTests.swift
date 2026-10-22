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

@Suite struct BubbleLayoutTests {
    let bounds = CGSize(width: 600, height: 500)
    let sizes: [Int64] = [900, 400, 300, 200, 120, 80, 50, 30, 20, 10, 8, 5, 3, 2, 1]

    func overlaps(_ bubbles: [BubbleLayout.Bubble], gap: CGFloat = 6) -> Bool {
        for i in bubbles.indices { for j in bubbles.indices where j > i {
            let a = bubbles[i], b = bubbles[j]
            if hypot(a.center.x - b.center.x, a.center.y - b.center.y) < a.radius + b.radius + gap - 1.5 { return true }
        } }
        return false
    }

    @Test func hoveringASmallBubbleGrowsItAndPushesNeighbors() {
        let base = BubbleLayout.layout(sizes: sizes, in: bounds)
        #expect(!overlaps(base))
        for hovered in [0, 3, 10, 14] {
            let spread = BubbleLayout.spread(base, hovered: hovered, in: bounds)
            #expect(spread[hovered].radius > base[hovered].radius)
            #expect(!overlaps(spread), "hovered \(hovered)")
            for b in spread {
                #expect(b.center.x >= 0 && b.center.x <= bounds.width && b.center.y >= 0 && b.center.y <= bounds.height)
            }
        }
    }

    @Test func pointerFindsTheBubbleUnderIt() {
        let base = BubbleLayout.layout(sizes: sizes, in: bounds)
        for b in base {
            #expect(BubbleLayout.bubble(at: b.center, in: base, current: nil) == b.index)
        }
        #expect(BubbleLayout.bubble(at: .zero, in: base, current: nil) == nil)
    }
}
