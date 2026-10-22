import Foundation

/// Last line of defense before anything is moved to the Trash or deleted.
///
/// Every removal in the app goes through `check(_:policy:)`. Rules and scanners decide
/// *what is worth cleaning*; the guard decides *what may never be touched*, whatever a rule,
/// a bug or a user click asks for. Hard-protected paths come partly from Mole's
/// SAFETY_WHITELIST_PATTERNS (GPL-3.0, github.com/tw93/Mole).
public struct SafetyGuard: Sendable {
    public enum Policy: Sendable {
        /// Items picked by a scanner rule. Strictest: user content folders are off-limits.
        case automatic
        /// Items the user picked by hand (Storage Map...). User files are allowed.
        case userInitiated
        /// Uninstalling an app: its bundle, preferences, containers and launch agents, in the home
        /// folder and in the system-wide Library. Apple's own apps and data are never allowed.
        case appRemoval
        /// Commands run by the privileged helper. Same scope as `appRemoval`.
        case administrator

        var reachesSystemLibrary: Bool { self == .appRemoval || self == .administrator }
    }

    public enum Verdict: Equatable, Sendable {
        case allowed
        case blocked(reason: String)

        public var isAllowed: Bool { self == .allowed }
    }

    public let home: URL
    public var userExclusions: [URL]

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, userExclusions: [URL] = []) {
        self.home = home
        self.userExclusions = userExclusions
    }

    /// System locations that are never touched by this app.
    static let systemRoots = [
        "/System", "/bin", "/sbin", "/usr", "/etc", "/private", "/var", "/tmp", "/cores", "/opt",
        "/Library", "/Applications", "/Users/Shared", "/Network",
    ]

    /// Home sub-paths that are never touched, under any policy.
    static let hardProtectedInHome = [
        "Library/Keychains", "Library/Mobile Documents", "Library/CloudStorage", "Library/Mail",
        "Library/Messages", "Library/Photos", "Library/Accounts", "Library/Cookies",
        "Library/Application Support/com.apple.TCC", "Library/Application Support/MobileSync",
        "Library/Group Containers", "Library/Preferences", "Library/LaunchAgents",
        ".ssh", ".gnupg", ".config", ".aws", ".kube", ".docker",
    ]

    /// Caches whose removal breaks macOS search, font rendering or iCloud sync
    /// instead of simply being rebuilt (from Mole's safety whitelist).
    static let hardProtectedCachePrefixes = [
        "com.apple.FontRegistry", "com.apple.spotlight", "com.apple.Spotlight", "CloudKit",
        "com.apple.finder", "com.apple.HomeKit", "com.apple.akd", "FamilyCircle", "com.apple.bird",
    ]

    /// Home sub-paths an uninstaller may reach although they are otherwise protected.
    static let appDataInHome = ["Library/Preferences", "Library/Group Containers", "Library/LaunchAgents", "Library/Cookies"]

    /// System folders where third-party apps install support files.
    static let systemRemovableRoots = [
        "/Library/LaunchAgents", "/Library/LaunchDaemons", "/Library/PrivilegedHelperTools",
        "/Library/Application Support", "/Library/Caches", "/Library/Logs", "/Library/Preferences",
        "/Library/Internet Plug-Ins", "/Library/Input Methods", "/Library/Screen Savers", "/Library/PreferencePanes",
        "/Library/QuickLook", "/Library/Spotlight", "/Library/Audio/Plug-Ins/Components", "/Library/Audio/Plug-Ins/HAL",
        "/Library/Audio/Plug-Ins/VST", "/Library/Audio/Plug-Ins/VST3",
    ]

    /// Folders holding the user's own documents. Rules never reach into them automatically.
    static let userContentFolders = ["Documents", "Desktop", "Pictures", "Movies", "Music", "Downloads", "Public", "Sites"]

    public func check(_ url: URL, policy: Policy) -> Verdict {
        let verdict = checkPath(url, policy: policy)
        guard verdict.isAllowed else { return verdict }
        // A symlinked ancestor could point anywhere: validate where the item really lives too,
        // against the home folder resolved the same way (e.g. /tmp → /private/tmp).
        let resolved = url.deletingLastPathComponent().resolvingSymlinksInPath().appending(path: url.lastPathComponent)
        let resolvedHome = home.resolvingSymlinksInPath()
        if resolved.normalizedPath != url.normalizedPath || resolvedHome.normalizedPath != home.normalizedPath {
            let canonical = SafetyGuard(home: resolvedHome, userExclusions: userExclusions.map { $0.resolvingSymlinksInPath() })
            return canonical.checkPath(resolved, policy: policy)
        }
        return .allowed
    }

    private func checkPath(_ url: URL, policy: Policy) -> Verdict {
        let path = url.normalizedPath
        let homePath = home.normalizedPath

        guard url.isFileURL, path.hasPrefix("/"), path != "/" else { return .blocked(reason: "Invalid path") }
        if path.split(separator: "/").contains("..") { return .blocked(reason: "Invalid path") }

        for exclusion in userExclusions where url.isInside(exclusion) {
            return .blocked(reason: "Excluded in Settings")
        }

        if path.hasPrefix("/Volumes/") {
            // Only the Trash folders of external volumes are reachable, never their content.
            let parts = path.split(separator: "/")
            guard parts.count >= 4, parts[2] == ".Trashes" else { return .blocked(reason: "External volume content") }
            return .allowed
        }

        guard url.isInside(home), path != homePath else {
            if policy.reachesSystemLibrary, let verdict = checkSystemItem(url) { return verdict }
            if Self.systemRoots.contains(where: { url.isInside(URL(filePath: $0)) }) {
                return .blocked(reason: "System location")
            }
            return .blocked(reason: "Outside your home folder")
        }

        let relative = String(path.dropFirst(homePath.count + 1))
        let components = relative.split(separator: "/").map(String.init)

        // Top-level folders (~/Documents, ~/Library...) are never removed themselves.
        if components.count == 1 { return .blocked(reason: "Top-level folder") }
        // Neither are the direct children of ~/Library (~/Library/Caches, ~/Library/Mail...).
        if components.first == "Library", components.count == 2 { return .blocked(reason: "Library folder") }

        for protected in Self.hardProtectedInHome {
            if relative == protected || relative.hasPrefix(protected + "/") {
                let isAppData = policy.reachesSystemLibrary && Self.appDataInHome.contains(protected) && components.count >= 3
                if !isAppData { return .blocked(reason: "Protected location") }
            }
        }

        if policy.reachesSystemLibrary {
            // Apple's own data is never part of an app removal.
            if components.first == "Library", components.count >= 3, Self.isAppleName(components[2]) {
                return .blocked(reason: "Belongs to macOS")
            }
            if components.first == "Applications", let verdict = checkAppBundle(url, depth: components.count - 1) {
                return verdict
            }
        }

        if components.count >= 3, components[0] == "Library", components[1] == "Caches",
           Self.hardProtectedCachePrefixes.contains(where: { components[2].hasPrefix($0) }) {
            return .blocked(reason: "System cache that macOS cannot rebuild safely")
        }

        // Never reach inside a Photos library package; the package as a whole is fine for the user to remove.
        if let index = components.firstIndex(where: { $0.hasSuffix(".photoslibrary") }), index < components.count - 1 {
            return .blocked(reason: "Inside a Photos library")
        }

        if policy == .automatic, let first = components.first, Self.userContentFolders.contains(first) {
            return .blocked(reason: "User documents")
        }

        return .allowed
    }

    /// Verdict for an item outside the home folder under an app-removal policy, or nil to fall back.
    private func checkSystemItem(_ url: URL) -> Verdict? {
        let path = url.normalizedPath
        if path.hasPrefix("/Applications/") {
            let depth = path.split(separator: "/").count - 1
            return checkAppBundle(url, depth: depth) ?? .blocked(reason: "Inside an application")
        }
        for root in Self.systemRemovableRoots where path.hasPrefix(root + "/") {
            let first = path.dropFirst(root.count + 1).split(separator: "/").first.map(String.init) ?? ""
            return Self.isAppleName(first) ? .blocked(reason: "Belongs to macOS") : .allowed
        }
        return nil
    }

    /// Only whole app bundles may go: `Applications/X.app` or `Applications/Folder/X.app`, never Apple's.
    private func checkAppBundle(_ url: URL, depth: Int) -> Verdict? {
        let isBundle = url.pathExtension == "app"
        guard isBundle, depth <= 2 else {
            let insideBundle = url.pathComponents.dropLast().contains { $0.hasSuffix(".app") }
            return insideBundle ? .blocked(reason: "Inside an application") : nil
        }
        if let id = Bundle(url: url)?.bundleIdentifier, Self.isAppleName(id) {
            return .blocked(reason: "Apple application")
        }
        return .allowed
    }

    static func isAppleName(_ name: String) -> Bool {
        name.hasPrefix("com.apple.") || name == "com.apple" || name.hasPrefix("Apple")
    }
}
