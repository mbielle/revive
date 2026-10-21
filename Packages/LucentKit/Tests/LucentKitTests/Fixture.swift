import Foundation
@testable import LucentKit

/// A throwaway fake home folder in the temporary directory.
struct Fixture {
    let home: URL

    init() throws {
        // Resolve /var → /private/var so paths match what the SafetyGuard sees.
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appending(path: "LucentTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        home = root
    }

    /// Creates a file of `size` bytes at a path relative to the fake home.
    @discardableResult
    func file(_ relativePath: String, size: Int = 50_000) throws -> URL {
        let url = home.appending(path: relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x2A, count: size).write(to: url)
        return url
    }

    func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: home.appending(path: relativePath).path(percentEncoded: false))
    }

    var safetyGuard: SafetyGuard { SafetyGuard(home: home) }

    func cleanUp() {
        try? FileManager.default.removeItem(at: home)
    }
}
