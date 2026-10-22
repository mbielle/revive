import Foundation

public enum FileSizes {
    static let prefetchKeys: [URLResourceKey] = [
        .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
    ]

    /// Allocated size on disk of a file or a whole directory tree. Symbolic links are not followed.
    /// Unreadable children are skipped; `isComplete` tells whether anything was skipped.
    public static func allocatedSize(of url: URL) -> (bytes: Int64, isComplete: Bool) {
        allocatedSize(of: url, onFile: nil)
    }

    /// Same, calling `onFile` for every file measured so callers can report progress.
    public static func allocatedSize(of url: URL, onFile: ((URL) -> Void)?) -> (bytes: Int64, isComplete: Bool) {
        let values = try? url.resourceValues(forKeys: Set(prefetchKeys))
        if values?.isSymbolicLink == true { return (0, true) }
        if values?.isDirectory != true {
            return (Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0), values != nil)
        }

        var total: Int64 = 0
        var complete = true
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: prefetchKeys,
            options: [],
            errorHandler: { _, _ in
                complete = false
                return true
            }
        )
        while let child = enumerator?.nextObject() as? URL {
            guard let v = try? child.resourceValues(forKeys: Set(prefetchKeys)), v.isRegularFile == true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            onFile?(child)
        }
        return (total, complete)
    }

    public static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

extension URL {
    /// Absolute path with `~` expanded, `.`/`..` removed and no trailing slash.
    var normalizedPath: String {
        standardizedFileURL.path(percentEncoded: false).trimmingTrailingSlash
    }

    /// True if `self` is `other` or lives somewhere below it.
    func isInside(_ other: URL) -> Bool {
        let mine = normalizedPath
        let theirs = other.normalizedPath
        return mine == theirs || mine.hasPrefix(theirs == "/" ? "/" : theirs + "/")
    }
}

extension String {
    var trimmingTrailingSlash: String {
        var s = self
        while s.count > 1, s.hasSuffix("/") { s.removeLast() }
        return s
    }

    /// Expands a leading `~` to the given home folder.
    func expandingTilde(home: URL) -> String {
        guard hasPrefix("~") else { return self }
        return home.normalizedPath + dropFirst()
    }
}
