import Foundation

/// Read-only checks of the Mac's built-in protections, used by Smart Care's security check.
public enum SecurityCheck: String, CaseIterable, Sendable, Identifiable {
    case systemIntegrityProtection
    case gatekeeper
    case fileVault
    case firewall

    public var id: String { rawValue }
}

public struct SecurityCheckResult: Sendable, Identifiable {
    public enum State: Sendable { case enabled, disabled, unknown }
    public var id: SecurityCheck { check }
    public let check: SecurityCheck
    public let state: State
}

public enum SystemStatus {
    /// Runs all protection checks concurrently. Each one shells out to Apple's own tool.
    public static func securityChecks() async -> [SecurityCheckResult] {
        await withTaskGroup(of: SecurityCheckResult.self) { group in
            for check in SecurityCheck.allCases {
                group.addTask { SecurityCheckResult(check: check, state: state(of: check)) }
            }
            var results: [SecurityCheckResult] = []
            for await result in group { results.append(result) }
            return SecurityCheck.allCases.compactMap { check in results.first { $0.check == check } }
        }
    }

    static func state(of check: SecurityCheck) -> SecurityCheckResult.State {
        let output: String?
        let enabledMarker: String
        switch check {
        case .systemIntegrityProtection:
            output = run("/usr/bin/csrutil", ["status"])
            enabledMarker = "status: enabled"
        case .gatekeeper:
            output = run("/usr/sbin/spctl", ["--status"])
            enabledMarker = "assessments enabled"
        case .fileVault:
            output = run("/usr/bin/fdesetup", ["status"])
            enabledMarker = "FileVault is On"
        case .firewall:
            output = run("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"])
            enabledMarker = "enabled"
        }
        guard let output, !output.isEmpty else { return .unknown }
        let text = output.lowercased()
        if check == .firewall, text.contains("disabled") { return .disabled }
        return text.contains(enabledMarker.lowercased()) ? .enabled : .disabled
    }

    /// Version of Apple's XProtect malware definitions, if installed.
    public static func xprotectVersion() -> String? {
        let url = URL(filePath: "/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist")
        guard let plist = NSDictionary(contentsOf: url) else { return nil }
        return plist["CFBundleShortVersionString"] as? String
    }

    /// Capacity of the startup volume.
    public static func startupDisk() -> DiskSpace? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeLocalizedNameKey]
        guard let values = try? URL(filePath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return DiskSpace(name: values.volumeLocalizedName ?? "Macintosh HD", total: Int64(total), available: available)
    }

    /// True when the app can read files protected by macOS privacy rules (Full Disk Access).
    public static func hasFullDiskAccess(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let probes = [
            home.appending(path: "Library/Application Support/com.apple.TCC/TCC.db"),
            home.appending(path: "Library/Safari/Bookmarks.plist"),
        ]
        return probes.contains { (try? FileHandle(forReadingFrom: $0))?.closeAndReturnTrue() == true }
    }

    static func run(_ tool: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

public struct DiskSpace: Sendable {
    public let name: String
    public let total: Int64
    public let available: Int64
    public var used: Int64 { total - available }
    public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

private extension FileHandle {
    func closeAndReturnTrue() -> Bool {
        try? close()
        return true
    }
}
