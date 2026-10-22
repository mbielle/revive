import CryptoKit
import Foundation
import UniformTypeIdentifiers
import Vision

/// A file of the user's own content.
public struct ClutterFile: Identifiable, Hashable, Sendable {
    public var id: String { url.normalizedPath }
    public let url: URL
    public let size: Int64
    public let modified: Date?
    public let accessed: Date?

    public var asCleanupItem: CleanupItem { CleanupItem(url: url, ruleID: "clutter", size: size) }
}

/// Files with the same content, or photos that look alike.
public struct ClutterGroup: Identifiable, Hashable, Sendable {
    public let id: String
    /// Sorted so the first file is the one to keep.
    public let files: [ClutterFile]

    public init(id: String, files: [ClutterFile]) {
        self.id = id
        self.files = files
    }

    /// Space freed by keeping only the first file.
    public var reclaimable: Int64 { files.dropFirst().reduce(0) { $0 + $1.size } }
}

public struct ClutterResult: Sendable {
    public var duplicates: [ClutterGroup] = []
    public var similarPhotos: [ClutterGroup] = []
    public var largeOldFiles: [ClutterFile] = []
    public var screenshots: [ClutterFile] = []

    public init() {}
}

/// Scans the user's folders (Desktop, Documents, Downloads, Pictures, Movies, Music).
/// The Photos library and app data are never part of it.
public struct ClutterScanner: Sendable {
    public let home: URL
    public var folders = ["Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music"]
    public var largeFileThreshold: Int64 = 50_000_000
    public var oldAfterDays = 365
    public var duplicateMinimumSize: Int64 = 100_000
    public var maxPhotos = 3_000
    /// Vision feature-print distance under which two photos count as similar.
    public var similarityThreshold: Float = 0.32

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    public func scan(progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }) async -> ClutterResult {
        let files = collectFiles(progress: progress)
        var result = ClutterResult()

        let cutoff = Date.now.addingTimeInterval(-Double(oldAfterDays) * 86_400)
        result.largeOldFiles = files
            .filter { $0.size >= largeFileThreshold || ($0.size >= 10_000_000 && ($0.accessed ?? $0.modified ?? .now) < cutoff) }
            .sorted { $0.size > $1.size }
        result.screenshots = files.filter { Self.isScreenshot($0.url) }.sorted { ($0.modified ?? .distantPast) < ($1.modified ?? .distantPast) }

        progress(ScanProgress(currentPath: String(localized: "Comparing files…"), bytesFound: 0, itemCount: files.count))
        result.duplicates = findDuplicates(files)
        if Task.isCancelled { return result }

        progress(ScanProgress(currentPath: String(localized: "Comparing photos…"), bytesFound: 0, itemCount: files.count))
        result.similarPhotos = findSimilarPhotos(files, excluding: Set(result.duplicates.flatMap(\.files).map(\.id)))
        return result
    }

    // MARK: Files

    func collectFiles(progress: @escaping @Sendable (ScanProgress) -> Void) -> [ClutterFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isPackageKey, .totalFileAllocatedSizeKey, .contentModificationDateKey, .contentAccessDateKey, .isHiddenKey]
        var files: [ClutterFile] = []
        for folder in folders {
            guard let enumerator = FileManager.default.enumerator(
                at: home.appending(path: folder), includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles], errorHandler: { _, _ in true }
            ) else { continue }
            for case let url as URL in enumerator {
                if Task.isCancelled { return files }
                guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
                if values.isPackage == true {
                    // Photos libraries, apps and other bundles are not loose files.
                    enumerator.skipDescendants()
                    continue
                }
                guard values.isRegularFile == true else { continue }
                files.append(ClutterFile(url: url, size: Int64(values.totalFileAllocatedSize ?? 0),
                                         modified: values.contentModificationDate, accessed: values.contentAccessDate))
                if files.count % 2_000 == 0 {
                    progress(ScanProgress(currentPath: url.path(percentEncoded: false), bytesFound: 0, itemCount: files.count))
                }
            }
        }
        return files
    }

    static func isScreenshot(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        let prefixes = ["Screenshot", "Screen Shot", "Capture d’écran", "Capture d'écran", "Bildschirmfoto", "Captura de pantalla", "Schermafbeelding"]
        return prefixes.contains { name.hasPrefix($0) } && ["png", "jpg", "heic", "mov"].contains(url.pathExtension.lowercased())
    }

    // MARK: Duplicates

    /// Same size → same hash of the first and last 64 KB → same full SHA-256.
    func findDuplicates(_ files: [ClutterFile]) -> [ClutterGroup] {
        let bySize = Dictionary(grouping: files.filter { $0.size >= duplicateMinimumSize }, by: \.size).values.filter { $0.count > 1 }
        var groups: [ClutterGroup] = []
        for sameSize in bySize {
            if Task.isCancelled { break }
            let byPartial = Dictionary(grouping: sameSize) { Self.hash($0.url, partial: true) ?? UUID().uuidString }.values.filter { $0.count > 1 }
            for candidates in byPartial {
                let byFull = Dictionary(grouping: candidates) { Self.hash($0.url, partial: false) ?? UUID().uuidString }
                for (digest, same) in byFull where same.count > 1 {
                    groups.append(ClutterGroup(id: digest, files: Self.keepFirst(same)))
                }
            }
        }
        return groups.sorted { $0.reclaimable > $1.reclaimable }
    }

    /// The oldest copy is kept; ties go to the shortest path.
    static func keepFirst(_ files: [ClutterFile]) -> [ClutterFile] {
        files.sorted {
            let a = $0.modified ?? .distantFuture, b = $1.modified ?? .distantFuture
            return a != b ? a < b : $0.url.path.count < $1.url.path.count
        }
    }

    static func hash(_ url: URL, partial: Bool) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        let chunk = 1 << 20
        if partial {
            guard let head = try? handle.read(upToCount: 65_536) else { return nil }
            hasher.update(data: head)
            if let end = try? handle.seekToEnd(), end > 131_072 {
                try? handle.seek(toOffset: end - 65_536)
                if let tail = try? handle.read(upToCount: 65_536) { hasher.update(data: tail) }
            }
        } else {
            while let data = try? handle.read(upToCount: chunk), !data.isEmpty {
                hasher.update(data: data)
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Similar photos

    func findSimilarPhotos(_ files: [ClutterFile], excluding: Set<String>) -> [ClutterGroup] {
        let photos = files
            .filter { !excluding.contains($0.id) && Self.isPhoto($0.url) && !Self.isScreenshot($0.url) }
            .sorted { ($0.modified ?? .distantPast) < ($1.modified ?? .distantPast) }
            .prefix(maxPhotos)
        var prints: [(ClutterFile, VNFeaturePrintObservation)] = []
        for photo in photos {
            if Task.isCancelled { return [] }
            if let observation = Self.featurePrint(photo.url) { prints.append((photo, observation)) }
        }

        // Union-find over pairs close enough; photos are compared with neighbors in time only,
        // because similar shots are almost always taken together.
        var parent = Array(prints.indices)
        func root(_ i: Int) -> Int { parent[i] == i ? i : { parent[i] = root(parent[i]); return parent[i] }() }
        let window = 40
        for i in prints.indices {
            for j in (i + 1)..<min(i + 1 + window, prints.count) {
                var distance: Float = 0
                if (try? prints[i].1.computeDistance(&distance, to: prints[j].1)) != nil, distance < similarityThreshold {
                    parent[root(j)] = root(i)
                }
            }
        }
        let clusters = Dictionary(grouping: prints.indices, by: root).values.filter { $0.count > 1 }
        return clusters.map { indices in
            // Keep the biggest file: usually the best quality.
            let files = indices.map { prints[$0].0 }.sorted { $0.size > $1.size }
            return ClutterGroup(id: files[0].id, files: files)
        }
        .sorted { $0.reclaimable > $1.reclaimable }
    }

    static func isPhoto(_ url: URL) -> Bool {
        ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "webp"].contains(url.pathExtension.lowercased())
    }

    static func featurePrint(_ url: URL) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(url: url, options: [:])
        guard (try? handler.perform([request])) != nil else { return nil }
        return request.results?.first
    }
}
