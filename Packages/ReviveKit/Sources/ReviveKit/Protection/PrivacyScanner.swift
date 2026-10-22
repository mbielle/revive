import Foundation

/// A group of traces left by a browser or by macOS (history, cookies...).
public struct PrivacyItem: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case history, cookies, autofill, cache, recentItems
    }

    public var id: String { "\(owner)-\(kind.rawValue)" }
    public let owner: String
    /// Bundle id of the app that must be closed before cleaning.
    public let bundleID: String?
    public let kind: Kind
    public let files: [URL]
    public let size: Int64

    public var title: LocalizedText {
        switch kind {
        case .history: .init(en: "Browsing history", fr: "Historique de navigation")
        case .cookies: .init(en: "Cookies", fr: "Cookies")
        case .autofill: .init(en: "Autofill form data", fr: "Données de saisie automatique")
        case .cache: .init(en: "Cached web content", fr: "Contenu web en cache")
        case .recentItems: .init(en: "Recent documents, apps and servers", fr: "Documents, apps et serveurs récents")
        }
    }
}

public struct BrowserExtension: Identifiable, Hashable, Sendable {
    public var id: String { folder.normalizedPath }
    public let browser: String
    public let name: String
    public let version: String
    public let folder: URL
}

/// Finds privacy traces. Saved passwords and bookmarks are never part of the results.
public struct PrivacyScanner: Sendable {
    public let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    struct Browser {
        let name: String
        let bundleID: String
        /// Profile folders, relative to the home folder; `*` matches any profile.
        let profiles: [String]
        let history: [String]
        let cookies: [String]
        let autofill: [String]
        let cache: [String]
    }

    static let chromiumFiles = (
        history: ["History", "History-journal", "Visited Links", "Top Sites", "Top Sites-journal", "Shortcuts", "Shortcuts-journal"],
        cookies: ["Cookies", "Cookies-journal", "Network/Cookies", "Network/Cookies-journal"],
        autofill: ["Web Data", "Web Data-journal"],
        cache: ["Cache", "Code Cache", "GPUCache"]
    )

    static let browsers: [Browser] = {
        let chromium: [(String, String, String)] = [
            ("Google Chrome", "com.google.Chrome", "Library/Application Support/Google/Chrome"),
            ("Brave", "com.brave.Browser", "Library/Application Support/BraveSoftware/Brave-Browser"),
            ("Microsoft Edge", "com.microsoft.edgemac", "Library/Application Support/Microsoft Edge"),
            ("Arc", "company.thebrowser.Browser", "Library/Application Support/Arc/User Data"),
            ("Vivaldi", "com.vivaldi.Vivaldi", "Library/Application Support/Vivaldi"),
        ]
        var list = chromium.map { name, id, root in
            Browser(name: name, bundleID: id, profiles: ["\(root)/Default", "\(root)/Profile *"],
                    history: chromiumFiles.history, cookies: chromiumFiles.cookies,
                    autofill: chromiumFiles.autofill, cache: chromiumFiles.cache)
        }
        list.append(Browser(name: "Safari", bundleID: "com.apple.Safari", profiles: ["Library"],
                            history: ["Safari/History.db", "Safari/History.db-wal", "Safari/History.db-shm", "Safari/RecentlyClosedTabs.plist"],
                            cookies: ["Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"],
                            autofill: [], cache: ["Caches/com.apple.Safari"]))
        list.append(Browser(name: "Firefox", bundleID: "org.mozilla.firefox", profiles: ["Library/Application Support/Firefox/Profiles/*"],
                            history: [], // places.sqlite also holds bookmarks: left alone.
                            cookies: ["cookies.sqlite", "cookies.sqlite-wal"],
                            autofill: ["formhistory.sqlite"], cache: ["cache2"]))
        return list
    }()

    public func scan() -> [PrivacyItem] {
        let pattern = PathPattern(home: home)
        var items: [PrivacyItem] = []
        for browser in Self.browsers {
            let profiles = browser.profiles.flatMap { pattern.matches("~/" + $0) }
            guard !profiles.isEmpty else { continue }
            for (kind, names) in [(PrivacyItem.Kind.history, browser.history), (.cookies, browser.cookies), (.autofill, browser.autofill), (.cache, browser.cache)] {
                let files = profiles.flatMap { profile in names.map { profile.appending(path: $0) } }
                    .filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
                guard !files.isEmpty else { continue }
                let size = files.reduce(0) { $0 + FileSizes.allocatedSize(of: $1).bytes }
                items.append(PrivacyItem(owner: browser.name, bundleID: browser.bundleID, kind: kind, files: files, size: size))
            }
        }
        let recents = pattern.matches("~/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.Recent*")
        if !recents.isEmpty {
            items.append(PrivacyItem(owner: "macOS", bundleID: nil, kind: .recentItems, files: recents,
                                     size: recents.reduce(0) { $0 + FileSizes.allocatedSize(of: $1).bytes }))
        }
        return items
    }

    /// Extensions installed in Chromium browsers and Firefox.
    public func extensions() -> [BrowserExtension] {
        let pattern = PathPattern(home: home)
        var result: [BrowserExtension] = []
        for browser in Self.browsers where browser.name != "Safari" && browser.name != "Firefox" {
            for profile in browser.profiles.flatMap({ pattern.matches("~/" + $0) }) {
                for folder in pattern.matches(profile.path(percentEncoded: false) + "/Extensions/*") {
                    guard let version = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)))?.sorted().last,
                          let manifest = Self.manifest(folder.appending(path: version)) else { continue }
                    if manifest.name.isEmpty { continue }
                    result.append(BrowserExtension(browser: browser.name, name: manifest.name, version: manifest.version, folder: folder))
                }
            }
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func manifest(_ folder: URL) -> (name: String, version: String)? {
        guard let data = try? Data(contentsOf: folder.appending(path: "manifest.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var name = json["name"] as? String ?? ""
        // "__MSG_appName__" names are translated in _locales/<lang>/messages.json.
        if name.hasPrefix("__MSG_"), name.hasSuffix("__") {
            let key = String(name.dropFirst(6).dropLast(2))
            let locale = (json["default_locale"] as? String) ?? "en"
            if let messages = try? Data(contentsOf: folder.appending(path: "_locales/\(locale)/messages.json")),
               let dict = try? JSONSerialization.jsonObject(with: messages) as? [String: [String: Any]],
               let entry = dict.first(where: { $0.key.lowercased() == key.lowercased() })?.value["message"] as? String {
                name = entry
            }
        }
        return (name, json["version"] as? String ?? "")
    }

    // MARK: Wi-Fi

    /// Device name of the Wi-Fi interface, e.g. "en0".
    public static func wifiInterface() -> String? {
        let output = run("/usr/sbin/networksetup", ["-listallhardwareports"])
        let lines = output.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() where line.contains("Wi-Fi") || line.contains("AirPort") {
            if index + 1 < lines.count, lines[index + 1].hasPrefix("Device: ") {
                return String(lines[index + 1].dropFirst("Device: ".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// Networks this Mac joins automatically.
    public static func savedWiFiNetworks(interface: String) -> [String] {
        run("/usr/sbin/networksetup", ["-listpreferredwirelessnetworks", interface])
            .components(separatedBy: "\n")
            .dropFirst()
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func run(_ tool: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return text
    }
}
