import Foundation
import os

/// One folder or file in the Space Lens map. Immutable once built.
public final class FileNode: Identifiable, Sendable, Hashable {
    public var id: String { url.normalizedPath }
    public let url: URL
    public let name: String
    public let size: Int64
    public let isDirectory: Bool
    /// Biggest children, largest first. Tiny entries are folded into `otherSize`.
    public let children: [FileNode]
    /// Combined size of children too small to be listed one by one.
    public let otherSize: Int64
    /// Some content could not be read (permissions or Full Disk Access).
    public let isIncomplete: Bool

    public init(url: URL, name: String? = nil, size: Int64, isDirectory: Bool, children: [FileNode] = [],
                otherSize: Int64 = 0, isIncomplete: Bool = false) {
        self.url = url
        self.name = name ?? FileManager.default.displayName(atPath: url.path(percentEncoded: false))
        self.size = size
        self.isDirectory = isDirectory
        self.children = children
        self.otherSize = otherSize
        self.isIncomplete = isIncomplete
    }

    /// A copy of this tree without the given nodes; sizes of every ancestor are updated.
    public func removing(_ ids: Set<String>) -> FileNode {
        let affected = children.contains { child in
            ids.contains { $0 == child.id || $0.hasPrefix(child.id + "/") }
        }
        guard affected else { return self }
        let kept = children.filter { !ids.contains($0.id) }.map { $0.removing(ids) }
        let newSize = kept.reduce(otherSize) { $0 + $1.size }
        return FileNode(url: url, name: name, size: newSize, isDirectory: isDirectory, children: kept,
                        otherSize: otherSize, isIncomplete: isIncomplete)
    }

    /// Finds a node by id anywhere below (or at) this node.
    public func node(withID id: String) -> FileNode? {
        if self.id == id { return self }
        guard id.hasPrefix(self.id == "/" ? "/" : self.id + "/") else { return nil }
        for child in children {
            if let found = child.node(withID: id) { return found }
        }
        return nil
    }

    public static func == (lhs: FileNode, rhs: FileNode) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

/// Measures a folder tree for Space Lens.
public struct SpaceScanner: Sendable {
    /// Entries smaller than this are not listed individually.
    public var minimumListedSize: Int64 = 1_000_000
    /// Maximum number of children kept per folder.
    public var maximumChildren = 60
    /// Folders scanned in parallel down to this depth.
    public var parallelDepth = 2
    /// Never descended into: other volumes and the firmlinked copy of the data volume.
    public static let skippedPaths: Set<String> = ["/Volumes", "/System/Volumes", "/dev", "/net", "/home", "/private/var/vm"]

    public init() {}

    public func scan(_ root: URL, progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }) async throws -> FileNode {
        let counter = Counter(progress: progress)
        let node = try await scanDirectory(root, depth: 0, counter: counter)
        counter.flush()
        return node
    }

    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
    ]

    private func scanDirectory(_ url: URL, depth: Int, counter: Counter) async throws -> FileNode {
        try Task.checkCancellation()
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: Self.keys, options: [])
        } catch {
            return FileNode(url: url, size: 0, isDirectory: true, isIncomplete: true)
        }

        var files: [FileNode] = []
        var folders: [URL] = []
        var incomplete = false
        for child in contents {
            if Self.skippedPaths.contains(child.path(percentEncoded: false)) { continue }
            guard let v = try? child.resourceValues(forKeys: Set(Self.keys)) else { incomplete = true; continue }
            if v.isSymbolicLink == true { continue }
            if v.isDirectory == true {
                if v.isPackage == true {
                    // Apps and other bundles are shown as a single item, like Finder does.
                    let (size, complete) = FileSizes.allocatedSize(of: child) { counter.tick($0) }
                    files.append(FileNode(url: child, size: size, isDirectory: false, isIncomplete: !complete))
                } else {
                    folders.append(child)
                }
            } else {
                files.append(FileNode(url: child, size: Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0), isDirectory: false))
            }
            counter.tick(child)
        }

        var subfolders: [FileNode] = []
        if depth < parallelDepth {
            subfolders = try await withThrowingTaskGroup(of: FileNode.self) { group in
                for folder in folders {
                    group.addTask { try await scanDirectory(folder, depth: depth + 1, counter: counter) }
                }
                var nodes: [FileNode] = []
                for try await node in group { nodes.append(node) }
                return nodes
            }
        } else {
            for folder in folders {
                subfolders.append(try await scanDirectory(folder, depth: depth + 1, counter: counter))
            }
        }

        let all = (files + subfolders).sorted { $0.size > $1.size }
        let total = all.reduce(0) { $0 + $1.size }
        let listed = Array(all.prefix { $0.size >= minimumListedSize }.prefix(maximumChildren))
        let other = total - listed.reduce(0) { $0 + $1.size }
        incomplete = incomplete || subfolders.contains(where: \.isIncomplete)
        return FileNode(url: url, size: total, isDirectory: true, children: listed, otherSize: other, isIncomplete: incomplete)
    }

    /// Throttles progress callbacks: at most about five per second, but never silent for long,
    /// even while a single huge bundle (an app, a Photos library) is being measured.
    final class Counter: Sendable {
        private let state = OSAllocatedUnfairLock(initialState: (count: 0, last: Date.distantPast))
        private let progress: @Sendable (ScanProgress) -> Void

        init(progress: @escaping @Sendable (ScanProgress) -> Void) { self.progress = progress }

        func tick(_ url: URL) {
            let report: Int? = state.withLock { s in
                s.count += 1
                let now = Date.now
                guard now.timeIntervalSince(s.last) > 0.2 else { return nil }
                s.last = now
                return s.count
            }
            if let report {
                progress(ScanProgress(currentPath: url.path(percentEncoded: false), bytesFound: 0, itemCount: report))
            }
        }

        func flush() {
            let count = state.withLock { $0.count }
            progress(ScanProgress(currentPath: "", bytesFound: 0, fraction: 1, itemCount: count))
        }
    }
}
