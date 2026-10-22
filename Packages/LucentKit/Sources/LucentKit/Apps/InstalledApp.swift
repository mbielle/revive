import CoreServices
import Foundation

/// An application bundle found in /Applications or ~/Applications.
public struct InstalledApp: Identifiable, Hashable, Sendable {
    public enum Source: Hashable, Sendable {
        case appStore
        case sparkle(feed: URL)
        case homebrew(token: String)
        case other
    }

    public var id: String { url.normalizedPath }
    public let url: URL
    public let name: String
    public let bundleID: String?
    public let version: String
    public let build: String
    public var size: Int64
    public let lastUsed: Date?
    public var source: Source
    public let isApple: Bool

    public init(url: URL, name: String, bundleID: String?, version: String, build: String, size: Int64,
                lastUsed: Date?, source: Source, isApple: Bool) {
        self.url = url
        self.name = name
        self.bundleID = bundleID
        self.version = version
        self.build = build
        self.size = size
        self.lastUsed = lastUsed
        self.source = source
        self.isApple = isApple
    }

    /// Not opened for `days` days according to Spotlight.
    public func isUnused(days: Int = 90, now: Date = .now) -> Bool {
        guard let lastUsed else { return false }
        return lastUsed < now.addingTimeInterval(-Double(days) * 86_400)
    }

    public var homebrewToken: String? {
        if case let .homebrew(token) = source { token } else { nil }
    }
}

/// Lists installed applications.
public struct AppInventory: Sendable {
    public var roots: [URL]
    /// Folders where Homebrew keeps installed casks.
    public var caskrooms = [URL(filePath: "/opt/homebrew/Caskroom"), URL(filePath: "/usr/local/Caskroom")]
    /// Measuring every bundle is the slow part; quick checks (updates) can skip it.
    public var measuresSizes = true

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        roots = [URL(filePath: "/Applications"), home.appending(path: "Applications")]
    }

    public func scan() async -> [InstalledApp] {
        let bundles = roots.flatMap(Self.appBundles(in:))
        let casks = homebrewCasks()
        let measure = measuresSizes
        return await withTaskGroup(of: InstalledApp?.self) { group in
            for url in bundles {
                group.addTask { Self.describe(url, casks: casks, measure: measure) }
            }
            var apps: [InstalledApp] = []
            for await app in group { if let app { apps.append(app) } }
            return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    /// `.app` bundles directly in `root` or one folder below it (e.g. /Applications/Utilities).
    static func appBundles(in root: URL) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        var result: [URL] = []
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true { continue }
            if entry.pathExtension == "app" {
                result.append(entry)
            } else if values?.isDirectory == true,
                      let nested = try? fm.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                result.append(contentsOf: nested.filter { $0.pathExtension == "app" })
            }
        }
        return result
    }

    static func describe(_ url: URL, casks: [String: String], measure: Bool = true) -> InstalledApp? {
        guard let bundle = Bundle(url: url) else { return nil }
        let info = bundle.infoDictionary ?? [:]
        let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
        let bundleID = bundle.bundleIdentifier
        let fileName = url.deletingPathExtension().lastPathComponent

        var source = InstalledApp.Source.other
        if FileManager.default.fileExists(atPath: url.appending(path: "Contents/_MASReceipt/receipt").path(percentEncoded: false)) {
            source = .appStore
        } else if let token = casks[url.lastPathComponent] {
            source = .homebrew(token: token)
        } else if let feed = (info["SUFeedURL"] as? String).flatMap(URL.init(string:)), feed.scheme?.hasPrefix("http") == true {
            source = .sparkle(feed: feed)
        }

        return InstalledApp(
            url: url,
            name: name.isEmpty ? fileName : name,
            bundleID: bundleID,
            version: (info["CFBundleShortVersionString"] as? String) ?? "",
            build: (info["CFBundleVersion"] as? String) ?? "",
            size: measure ? FileSizes.allocatedSize(of: url).bytes : 0,
            lastUsed: lastUsedDate(url),
            source: source,
            isApple: bundleID.map { $0.hasPrefix("com.apple.") } ?? false
        )
    }

    static func lastUsedDate(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    /// App file name ("Visual Studio Code.app") → cask token ("visual-studio-code").
    func homebrewCasks() -> [String: String] {
        var map: [String: String] = [:]
        let fm = FileManager.default
        for room in caskrooms {
            guard let tokens = try? fm.contentsOfDirectory(atPath: room.path(percentEncoded: false)) else { continue }
            for token in tokens where !token.hasPrefix(".") {
                for app in Self.caskApps(token: token, caskroom: room) { map[app] = token }
            }
        }
        return map
    }

    /// Names of the `app` artifacts declared in the cask's installed metadata.
    static func caskApps(token: String, caskroom: URL) -> [String] {
        let metadata = caskroom.appending(path: "\(token)/.metadata")
        guard let enumerator = FileManager.default.enumerator(at: metadata, includingPropertiesForKeys: nil) else { return [] }
        for case let file as URL in enumerator where file.lastPathComponent == "\(token).json" {
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let artifacts = json["artifacts"] as? [Any] else { continue }
            var apps: [String] = []
            for artifact in artifacts {
                guard let dict = artifact as? [String: Any], let values = dict["app"] as? [Any] else { continue }
                apps += values.compactMap { $0 as? String }.map { ($0 as NSString).lastPathComponent }
            }
            if !apps.isEmpty { return apps }
        }
        return []
    }
}
