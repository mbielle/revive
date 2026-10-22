import Foundation
import Security

/// A launchd job installed by an app: runs in the background or at login.
public struct LaunchItem: Identifiable, Hashable, Sendable {
    public enum Scope: String, Sendable, CaseIterable {
        /// ~/Library/LaunchAgents: runs as you, removable without a password.
        case userAgent
        /// /Library/LaunchAgents: runs as every user.
        case globalAgent
        /// /Library/LaunchDaemons: runs as root.
        case daemon
    }

    public var id: String { plist.normalizedPath }
    public let label: String
    public let plist: URL
    public let scope: Scope
    public let program: String?
    public let runsAtLoad: Bool
    public let keepsAlive: Bool
    public let isDisabled: Bool
    /// Loaded in launchd right now (known for user agents only).
    public var isLoaded: Bool?
    /// Who signed the program, e.g. "Developer ID Application: Google LLC (EQHXZ8M8AV)".
    public var signer: String?

    public var requiresAdministrator: Bool { scope != .userAgent }
}

public struct LaunchItemScanner: Sendable {
    public let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    public func scan() -> [LaunchItem] {
        let loaded = Self.loadedUserLabels()
        let sources: [(URL, LaunchItem.Scope)] = [
            (home.appending(path: "Library/LaunchAgents"), .userAgent),
            (URL(filePath: "/Library/LaunchAgents"), .globalAgent),
            (URL(filePath: "/Library/LaunchDaemons"), .daemon),
        ]
        var items: [LaunchItem] = []
        for (folder, scope) in sources {
            guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { continue }
            for file in files where file.pathExtension == "plist" {
                guard var item = Self.parse(file, scope: scope) else { continue }
                if item.label.hasPrefix("com.apple.") { continue }
                if scope == .userAgent { item.isLoaded = loaded.contains(item.label) }
                item.signer = item.program.flatMap(CodeSignature.signer(ofPath:))
                items.append(item)
            }
        }
        return items.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    static func parse(_ plist: URL, scope: LaunchItem.Scope) -> LaunchItem? {
        guard let dict = NSDictionary(contentsOf: plist) as? [String: Any] else { return nil }
        let label = (dict["Label"] as? String) ?? plist.deletingPathExtension().lastPathComponent
        let program = (dict["Program"] as? String) ?? (dict["ProgramArguments"] as? [String])?.first
        let keepAlive: Bool = {
            if let flag = dict["KeepAlive"] as? Bool { return flag }
            return dict["KeepAlive"] is [String: Any]
        }()
        return LaunchItem(label: label, plist: plist, scope: scope, program: program,
                          runsAtLoad: (dict["RunAtLoad"] as? Bool) ?? false, keepsAlive: keepAlive,
                          isDisabled: (dict["Disabled"] as? Bool) ?? false)
    }

    /// Labels currently loaded in the user's launchd domain.
    static func loadedUserLabels() -> Set<String> {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/launchctl")
        process.arguments = ["list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return Set(text.split(separator: "\n").dropFirst().compactMap { line in
            line.split(separator: "\t").last.map(String.init)
        })
    }

    /// Unloads a user agent and moves its plist to the Trash.
    public static func removeUserAgent(_ item: LaunchItem, dryRun: Bool) throws {
        guard item.scope == .userAgent else { return }
        if dryRun { return }
        _ = run("/bin/launchctl", ["bootout", "gui/\(getuid())", item.plist.path(percentEncoded: false)])
        try FileManager.default.trashItem(at: item.plist, resultingItemURL: nil)
    }

    /// Stops or starts a user agent without removing it.
    public static func setUserAgent(_ item: LaunchItem, loaded: Bool) -> Bool {
        guard item.scope == .userAgent else { return false }
        let domain = "gui/\(getuid())"
        if loaded {
            _ = run("/bin/launchctl", ["enable", "\(domain)/\(item.label)"])
            return run("/bin/launchctl", ["bootstrap", domain, item.plist.path(percentEncoded: false)]) == 0
        } else {
            let status = run("/bin/launchctl", ["bootout", domain, item.plist.path(percentEncoded: false)])
            _ = run("/bin/launchctl", ["disable", "\(domain)/\(item.label)"])
            return status == 0
        }
    }

    @discardableResult
    static func run(_ tool: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}

/// Code signature helpers shared by Performance and Protection.
public enum CodeSignature {
    public struct Info: Sendable, Hashable {
        public let signer: String?
        public let teamID: String?
        public let isSigned: Bool
        public let isAppleSigned: Bool
    }

    public static func info(ofPath path: String) -> Info {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(filePath: path) as CFURL, [], &code) == errSecSuccess, let code else {
            return Info(signer: nil, teamID: nil, isSigned: false, isAppleSigned: false)
        }
        let valid = SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), nil) == errSecSuccess
        var dict: CFDictionary?
        SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &dict)
        let information = dict as? [String: Any] ?? [:]
        let certificates = information[kSecCodeInfoCertificates as String] as? [SecCertificate]
        let signer = certificates?.first.flatMap { SecCertificateCopySubjectSummary($0) as String? }
        var requirement: SecRequirement?
        SecRequirementCreateWithString("anchor apple" as CFString, [], &requirement)
        let isApple = requirement.map { SecStaticCodeCheckValidity(code, [], $0) == errSecSuccess } ?? false
        return Info(signer: signer, teamID: information[kSecCodeInfoTeamIdentifier as String] as? String,
                    isSigned: valid && signer != nil, isAppleSigned: isApple)
    }

    public static func signer(ofPath path: String) -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return info(ofPath: path).signer
    }
}
