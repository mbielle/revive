import Foundation

/// Finds the files an app spreads around the system, and the files of apps that are gone.
///
/// Matching is deliberately strict (exact bundle id or exact app name) so the uninstaller never
/// proposes files of another app. Missing an obscure leftover is better than deleting a wrong one.
public struct LeftoverFinder: Sendable {
    public let home: URL
    public let safetyGuard: SafetyGuard
    /// Prefix for system-wide folders; replaced in tests.
    public var systemRoot = URL(filePath: "/")

    public init(safetyGuard: SafetyGuard) {
        self.home = safetyGuard.home
        self.safetyGuard = safetyGuard
    }

    /// Folders searched by bundle id, relative to a Library folder.
    static let bundleIDFolders = [
        "Application Support", "Caches", "Containers", "Group Containers", "Preferences", "Preferences/ByHost",
        "Saved Application State", "HTTPStorages", "WebKit", "Logs", "Cookies", "LaunchAgents", "Application Scripts",
    ]
    /// Bundle-id-like names used by developer tools and shared frameworks rather than by apps.
    static let toolPrefixes = [
        "org.swift.", "com.breakpad.", "com.github.", "org.python.", "org.nodejs.", "org.llvm.", "io.flutter.",
        "com.docker.", "org.sparkle-project.", "com.crashlytics.", "io.sentry.", "com.google.keystone", "org.mozilla.",
        "com.microsoft.autoupdate", "com.microsoft.vscode", "com.jetbrains.", "org.r-project.",
    ]

    /// Folders searched by app name, relative to a Library folder.
    static let nameFolders = ["Application Support", "Caches", "Logs"]
    /// System folders searched by bundle id.
    static let systemBundleIDFolders = [
        "Library/Application Support", "Library/Caches", "Library/Preferences", "Library/LaunchAgents",
        "Library/LaunchDaemons", "Library/PrivilegedHelperTools", "Library/Logs",
    ]

    /// Everything that belongs to `app`, including the app bundle itself as the first item.
    public func files(for app: InstalledApp) -> [CleanupItem] {
        var urls: [URL] = [app.url]
        let library = home.appending(path: "Library")

        if let bundleID = app.bundleID, bundleID.split(separator: ".").count >= 2 {
            for folder in Self.bundleIDFolders {
                urls += children(of: library.appending(path: folder)) { Self.name($0, matches: bundleID) }
            }
            for folder in Self.systemBundleIDFolders {
                urls += children(of: systemRoot.appending(path: folder)) { Self.name($0, matches: bundleID) }
            }
        }
        if app.name.count >= 4 {
            for folder in Self.nameFolders {
                urls += children(of: library.appending(path: folder)) { $0.caseInsensitiveCompare(app.name) == .orderedSame }
                urls += children(of: systemRoot.appending(path: "Library/\(folder)")) { $0.caseInsensitiveCompare(app.name) == .orderedSame }
            }
        }

        var seen = Set<String>()
        return urls.compactMap { url in
            let path = url.normalizedPath
            guard seen.insert(path).inserted, !seen.contains(where: { path.hasPrefix($0 + "/") }) else { return nil }
            guard safetyGuard.check(url, policy: .appRemoval).isAllowed else { return nil }
            let (size, complete) = FileSizes.allocatedSize(of: url)
            return CleanupItem(url: url, ruleID: url == app.url ? "app-bundle" : "app-leftover", size: size, isSizeComplete: complete)
        }
    }

    /// Support files whose app is no longer installed.
    public func orphans(installed: [InstalledApp], runningBundleIDs: Set<String>) -> [CleanupItem] {
        let installedIDs = installed.compactMap(\.bundleID).map { $0.lowercased() }
        let vendors = Set(installedIDs.map(Self.vendor))
        let running = runningBundleIDs.map { $0.lowercased() }
        let library = home.appending(path: "Library")
        let folders = ["Application Support", "Caches", "Containers", "Preferences", "Saved Application State", "HTTPStorages", "WebKit", "Logs"]

        var items: [CleanupItem] = []
        for folder in folders {
            for url in children(of: library.appending(path: folder), where: { _ in true }) {
                guard let id = Self.bundleIDLike(url.lastPathComponent)?.lowercased() else { continue }
                if id.hasPrefix("com.apple.") || id.hasPrefix("group.") { continue }
                if Self.toolPrefixes.contains(where: { id.hasPrefix($0) }) { continue }
                // Any installed or running app from the same vendor may still use it.
                if vendors.contains(Self.vendor(id)) { continue }
                if (installedIDs + running).contains(where: { id.hasPrefix($0) || $0.hasPrefix(id) }) { continue }
                guard safetyGuard.check(url, policy: .appRemoval).isAllowed else { continue }
                let (size, complete) = FileSizes.allocatedSize(of: url)
                guard size > 0 else { continue }
                items.append(CleanupItem(url: url, ruleID: "orphan", size: size, isSizeComplete: complete))
            }
        }
        return items.sorted { $0.size > $1.size }
    }

    /// Installer files left in Downloads and on the Desktop.
    public func installers() -> [CleanupItem] {
        let extensions: Set<String> = ["dmg", "pkg", "mpkg", "xip"]
        return ["Downloads", "Desktop"].flatMap { folder in
            children(of: home.appending(path: folder)) { extensions.contains(($0 as NSString).pathExtension.lowercased()) }
        }
        .filter { safetyGuard.check($0, policy: .userInitiated).isAllowed }
        .map { CleanupItem(url: $0, ruleID: "installer", size: FileSizes.allocatedSize(of: $0).bytes) }
        .sorted { $0.size > $1.size }
    }

    // MARK: Matching

    /// `com.x.app`, `com.x.app.plist`, `com.x.app.helper`, `TEAMID.com.x.app`, `com.x.app.savedState`...
    static func name(_ name: String, matches bundleID: String) -> Bool {
        let lower = name.lowercased(), id = bundleID.lowercased()
        return lower == id || lower.hasPrefix(id + ".") || lower.hasSuffix("." + id) || lower.contains("." + id + ".")
    }

    /// The bundle id a support file is named after, if its name looks like one.
    static func bundleIDLike(_ fileName: String) -> String? {
        var base = fileName
        for suffix in [".plist", ".savedState", ".binarycookies"] where base.hasSuffix(suffix) {
            base = String(base.dropLast(suffix.count))
        }
        let parts = base.split(separator: ".")
        guard parts.count >= 3, parts.allSatisfy({ !$0.isEmpty }),
              base.range(of: #"^[A-Za-z0-9-]+(\.[A-Za-z0-9_-]+){2,}$"#, options: .regularExpression) != nil,
              parts[0].count <= 6 else { return nil }
        return base
    }

    /// `com.vendor` part of a bundle id.
    static func vendor(_ bundleID: String) -> String {
        bundleID.split(separator: ".").prefix(2).joined(separator: ".")
    }

    private func children(of folder: URL, where predicate: (String) -> Bool) -> [URL] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) else { return [] }
        return names.filter { !$0.hasPrefix(".") && predicate($0) }.map { folder.appending(path: $0) }
    }
}
