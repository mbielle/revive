import Foundation

/// A newer version available for an installed app.
public struct AppUpdate: Identifiable, Hashable, Sendable {
    public var id: String { app.id }
    public let app: InstalledApp
    public let newVersion: String
    /// Where to get it: App Store page, release notes or download.
    public let link: URL?
}

/// Checks Sparkle feeds, the Mac App Store and Homebrew for newer versions.
/// Only contacts each app's own update server and Apple's public lookup API, and only on request.
public struct UpdateChecker: Sendable {
    public var session: URLSession = .shared
    public var countryCode = Locale.current.region?.identifier ?? "US"
    public var maxConcurrent = 8

    public init() {}

    public func check(_ apps: [InstalledApp]) async -> [AppUpdate] {
        let candidates = apps.filter { !$0.isApple }
        var updates: [AppUpdate] = []

        let brewApps = candidates.filter { $0.homebrewToken != nil }
        if !brewApps.isEmpty {
            updates += await homebrewUpdates(for: brewApps)
        }

        let others = candidates.filter { $0.homebrewToken == nil }
        await withTaskGroup(of: AppUpdate?.self) { group in
            var iterator = others.makeIterator()
            func addNext() -> Bool {
                guard let app = iterator.next() else { return false }
                group.addTask { await checkOne(app) }
                return true
            }
            for _ in 0..<maxConcurrent where addNext() {}
            for await update in group {
                if let update { updates.append(update) }
                _ = addNext()
            }
        }
        return updates.sorted { $0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending }
    }

    func checkOne(_ app: InstalledApp) async -> AppUpdate? {
        switch app.source {
        case let .sparkle(feed): await sparkleUpdate(app, feed: feed)
        case .appStore: await appStoreUpdate(app)
        default: nil
        }
    }

    // MARK: Sparkle

    func sparkleUpdate(_ app: InstalledApp, feed: URL) async -> AppUpdate? {
        guard let data = await fetch(feed) else { return nil }
        let items = AppcastParser.parse(data)
        guard let latest = items.max(by: { Version.compare($0.version, $1.version) == .orderedAscending }) else { return nil }
        // Sparkle compares the feed's sparkle:version with CFBundleVersion.
        let installed = app.build.isEmpty ? app.version : app.build
        guard Version.compare(latest.version, installed) == .orderedDescending else { return nil }
        if let minimum = latest.minimumSystemVersion, Version.compare(minimum, Self.systemVersion) == .orderedDescending {
            return nil
        }
        return AppUpdate(app: app, newVersion: latest.shortVersion ?? latest.version, link: latest.releaseNotes ?? latest.download)
    }

    static var systemVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    // MARK: App Store

    func appStoreUpdate(_ app: InstalledApp) async -> AppUpdate? {
        guard let bundleID = app.bundleID,
              var components = URLComponents(string: "https://itunes.apple.com/lookup") else { return nil }
        components.queryItems = [.init(name: "bundleId", value: bundleID), .init(name: "country", value: countryCode), .init(name: "entity", value: "macSoftware")]
        guard let url = components.url, let data = await fetch(url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = (json["results"] as? [[String: Any]])?.first,
              let version = result["version"] as? String else { return nil }
        guard Version.compare(version, app.version) == .orderedDescending else { return nil }
        let trackID = result["trackId"] as? Int
        let link = trackID.flatMap { URL(string: "macappstore://apps.apple.com/app/id\($0)") }
        return AppUpdate(app: app, newVersion: version, link: link)
    }

    // MARK: Homebrew

    public static var brewExecutable: URL? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].map { URL(filePath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path(percentEncoded: false)) }
    }

    func homebrewUpdates(for apps: [InstalledApp]) async -> [AppUpdate] {
        guard let brew = Self.brewExecutable else { return [] }
        let output: Data? = await Task.detached {
            let process = Process()
            process.executableURL = brew
            process.arguments = ["outdated", "--cask", "--json=v2"]
            var environment = ProcessInfo.processInfo.environment
            environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
            process.environment = environment
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return data
        }.value
        guard let output,
              let json = try? JSONSerialization.jsonObject(with: output) as? [String: Any],
              let casks = json["casks"] as? [[String: Any]] else { return [] }
        var latest: [String: String] = [:]
        for cask in casks {
            if let name = cask["name"] as? String, let version = cask["current_version"] as? String { latest[name] = version }
        }
        return apps.compactMap { app in
            guard let token = app.homebrewToken, let version = latest[token] else { return nil }
            return AppUpdate(app: app, newVersion: version.components(separatedBy: ",").first ?? version, link: nil)
        }
    }

    private func fetch(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("Revive (macOS update check)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}

/// Reads the items of a Sparkle appcast.
public enum AppcastParser {
    public struct Item: Sendable, Equatable {
        public var version: String
        public var shortVersion: String?
        public var minimumSystemVersion: String?
        public var download: URL?
        public var releaseNotes: URL?
    }

    public static func parse(_ data: Data) -> [Item] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.parse()
        return delegate.items.filter { !$0.version.isEmpty }
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var items: [Item] = []
        private var current: Item?
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            text = ""
            switch name {
            case "item":
                current = Item(version: "")
            case "enclosure":
                if let v = attributes["sparkle:version"] { current?.version = v }
                if let v = attributes["sparkle:shortVersionString"] { current?.shortVersion = v }
                if let url = attributes["url"].flatMap(URL.init(string:)) { current?.download = url }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch name {
            case "sparkle:version" where !value.isEmpty: current?.version = value
            case "sparkle:shortVersionString" where !value.isEmpty: current?.shortVersion = value
            case "sparkle:minimumSystemVersion" where !value.isEmpty: current?.minimumSystemVersion = value
            case "sparkle:releaseNotesLink": current?.releaseNotes = URL(string: value)
            case "item":
                if let item = current { items.append(item) }
                current = nil
            default: break
            }
            text = ""
        }
    }
}

/// Dotted version comparison that understands "1.10" > "1.9" and "2.0" == "2.0.0".
public enum Version {
    public static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let left = parts(a), right = parts(b)
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    static func parts(_ version: String) -> [Int] {
        // Keep the leading numeric part ("1.2.3 (456)" → [1, 2, 3]).
        let core = version.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "(" }).first.map(String.init) ?? version
        return core.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }
}
