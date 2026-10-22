import Darwin
import Foundation

/// Expands the glob patterns used by cleanup rules into real paths on disk.
struct PathPattern {
    let home: URL

    /// Placeholders available in rule paths besides `~`.
    private var substitutions: [String: String] {
        ["{uid}": String(getuid())]
    }

    func expandedPattern(_ pattern: String) -> String {
        var result = pattern.expandingTilde(home: home)
        for (key, value) in substitutions {
            result = result.replacingOccurrences(of: key, with: value)
        }
        return result
    }

    /// All existing paths matching `pattern`, sorted. Symbolic links are listed but never traversed.
    func matches(_ pattern: String) -> [URL] {
        let expanded = expandedPattern(pattern)
        guard expanded.hasPrefix("/") else { return [] }
        let components = expanded.split(separator: "/").map(String.init)

        var current = ["/"]
        for (index, component) in components.enumerated() {
            let isLast = index == components.count - 1
            var next: [String] = []
            for base in current {
                if Self.hasGlob(component) {
                    // Only descend into real directories, never through symlinks.
                    if base != "/", Self.isSymlink(base) { continue }
                    guard let children = try? FileManager.default.contentsOfDirectory(atPath: base) else { continue }
                    for child in children.sorted() where Self.matches(component, child) {
                        next.append(Self.join(base, child))
                    }
                } else {
                    // Literal components may be symlinks (e.g. /var); the SafetyGuard validates
                    // where each match really lives before anything is removed.
                    let path = Self.join(base, component)
                    if FileManager.default.fileExists(atPath: path) || (isLast && Self.isSymlink(path)) { next.append(path) }
                }
            }
            current = next
            if current.isEmpty { return [] }
        }
        return current.map { URL(filePath: $0) }
    }

    /// True if `url` or one of its ancestors matches one of the patterns.
    func isExcluded(_ url: URL, by patterns: [String]) -> Bool {
        guard !patterns.isEmpty else { return false }
        let expanded = patterns.map(expandedPattern)
        var path = url.normalizedPath
        while path != "/" && !path.isEmpty {
            for pattern in expanded where fnmatch(pattern, path, FNM_PATHNAME) == 0 {
                return true
            }
            path = (path as NSString).deletingLastPathComponent
        }
        return false
    }

    static func hasGlob(_ component: String) -> Bool {
        component.contains(where: { "*?[".contains($0) })
    }

    static func matches(_ glob: String, _ name: String) -> Bool {
        fnmatch(glob, name, 0) == 0
    }

    static func join(_ base: String, _ child: String) -> String {
        base == "/" ? "/" + child : base + "/" + child
    }

    static func isSymlink(_ path: String) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType) == .typeSymbolicLink
    }
}
