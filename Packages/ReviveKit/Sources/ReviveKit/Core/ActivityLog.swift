import Foundation

/// One entry of the "My Activity" history.
public struct ActivityEntry: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var date: Date
    /// Module that performed the action, e.g. "cleanup" or "spaceLens".
    public var module: String
    public var freedBytes: Int64
    public var itemCount: Int
    public var failureCount: Int
    public var wasSimulated: Bool

    public init(id: UUID = UUID(), date: Date = .now, module: String, freedBytes: Int64,
                itemCount: Int, failureCount: Int, wasSimulated: Bool) {
        self.id = id
        self.date = date
        self.module = module
        self.freedBytes = freedBytes
        self.itemCount = itemCount
        self.failureCount = failureCount
        self.wasSimulated = wasSimulated
    }
}

/// Persists the activity history as JSON in Application Support. Nothing ever leaves the Mac.
public actor ActivityLog {
    public static let shared = ActivityLog()

    private let fileURL: URL
    private var cache: [ActivityEntry]?

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? URL.applicationSupportDirectory
            .appending(path: "Revive", directoryHint: .isDirectory)
            .appending(path: "activity.json")
    }

    public func entries() -> [ActivityEntry] {
        if let cache { return cache }
        let loaded = (try? Data(contentsOf: fileURL)).flatMap {
            try? Self.decoder.decode([ActivityEntry].self, from: $0)
        } ?? []
        cache = loaded
        return loaded
    }

    public func append(_ entry: ActivityEntry) throws {
        var all = entries()
        all.insert(entry, at: 0)
        cache = all
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(all).write(to: fileURL, options: .atomic)
    }

    public func clear() throws {
        cache = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
