import Foundation

/// A cloud storage service synced to this Mac.
public struct CloudProvider: Identifiable, Hashable, Sendable {
    public var id: String { root.normalizedPath }
    public let name: String
    public let root: URL
    /// Size of everything in the folder, downloaded or not.
    public let totalSize: Int64
    /// Space the downloaded copies take on this Mac.
    public let localSize: Int64
    /// Biggest files that are downloaded locally.
    public let largestLocalFiles: [ClutterFile]
}

public struct CloudScanResult: Sendable {
    public var providers: [CloudProvider] = []
    /// Files in Downloads, Desktop or Documents that also exist in a cloud folder.
    public var localDuplicates: [ClutterFile] = []
    /// The iCloud Drive folder exists but cannot be read without Full Disk Access.
    public var iCloudUnreadable = false

    public init() {}
}

/// Finds what takes space in iCloud Drive, Google Drive, OneDrive, Dropbox... and frees local copies.
/// Files are never deleted from the cloud: removing a local copy keeps the file online.
public struct CloudScanner: Sendable {
    public let home: URL
    public var listedFiles = 40

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    public func scan() -> CloudScanResult {
        var result = CloudScanResult()
        var cloudFiles: [ClutterFile] = []

        var roots: [(String, URL)] = []
        let iCloud = home.appending(path: "Library/Mobile Documents/com~apple~CloudDocs")
        if FileManager.default.fileExists(atPath: iCloud.path(percentEncoded: false)) {
            if (try? FileManager.default.contentsOfDirectory(atPath: iCloud.path(percentEncoded: false))) != nil {
                roots.append(("iCloud Drive", iCloud))
            } else {
                result.iCloudUnreadable = true
            }
        }
        let storage = home.appending(path: "Library/CloudStorage")
        for folder in (try? FileManager.default.contentsOfDirectory(at: storage, includingPropertiesForKeys: nil)) ?? [] {
            roots.append((Self.providerName(folder.lastPathComponent), folder))
        }

        for (name, root) in roots {
            let (provider, files) = measure(name: name, root: root)
            result.providers.append(provider)
            cloudFiles += files
        }

        // Same name and size in a local folder and in the cloud: very likely the same file twice.
        let index = Set(cloudFiles.filter { $0.size >= 1_000_000 }.map { "\($0.url.lastPathComponent)|\($0.size)" })
        if !index.isEmpty {
            var clutter = ClutterScanner(home: home)
            clutter.folders = ["Downloads", "Desktop", "Documents"]
            result.localDuplicates = clutter.collectFiles(progress: { _ in })
                .filter { index.contains("\($0.url.lastPathComponent)|\($0.size)") }
                .sorted { $0.size > $1.size }
        }
        return result
    }

    /// "GoogleDrive-me@gmail.com" → "Google Drive".
    static func providerName(_ folder: String) -> String {
        let base = folder.components(separatedBy: "-").first ?? folder
        switch base {
        case "GoogleDrive": return "Google Drive"
        case "OneDrive": return "OneDrive"
        case "Dropbox": return "Dropbox"
        case "Box": return "Box"
        case "pCloudDrive", "pCloud": return "pCloud"
        default: return base
        }
    }

    func measure(name: String, root: URL) -> (CloudProvider, [ClutterFile]) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey]
        var total: Int64 = 0, local: Int64 = 0
        var files: [ClutterFile] = []
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles], errorHandler: { _, _ in true })
        while let url = enumerator?.nextObject() as? URL {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            let logical = Int64(values.fileSize ?? 0)
            let allocated = Int64(values.totalFileAllocatedSize ?? 0)
            total += logical
            local += allocated
            files.append(ClutterFile(url: url, size: allocated > 0 ? allocated : logical, modified: values.contentModificationDate, accessed: nil))
        }
        let largest = files.filter { (try? $0.url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize ?? 0) ?? 0 > 0 }
            .sorted { $0.size > $1.size }
            .prefix(listedFiles)
        return (CloudProvider(name: name, root: root, totalSize: total, localSize: local, largestLocalFiles: Array(largest)), files)
    }

    /// Removes the downloaded copy; the file stays in the cloud and downloads again when opened.
    public static func removeLocalCopy(_ url: URL) throws {
        try FileManager.default.evictUbiquitousItem(at: url)
    }
}
