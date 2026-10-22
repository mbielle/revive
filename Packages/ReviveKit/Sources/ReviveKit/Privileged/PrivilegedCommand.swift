import Foundation

/// Mach service name of the privileged helper; also its launchd label.
public let helperServiceName = "io.github.mbielle.Revive.Helper"

/// The closed list of things the privileged helper is allowed to do.
///
/// Every command maps to fixed Apple tools with fixed arguments. Free-form input is limited to
/// launchd labels (validated) and paths (validated by the `SafetyGuard` in the helper itself).
public enum PrivilegedCommand: Codable, Sendable, Hashable {
    case flushDNS
    case freeMemory
    case reindexSpotlight
    case thinLocalSnapshots
    /// Dumps the Background Task Management database (login and background items).
    case listBackgroundItems
    /// Stops and unloads a system-wide launch daemon or agent.
    case bootout(label: String)
    /// Moves system-owned items into the Trash of the given user.
    case moveToTrash(paths: [String], uid: UInt32)
    /// Forgets a saved Wi-Fi network.
    case forgetWiFiNetwork(name: String, interface: String)

    /// Commands run in order; the first failure stops the sequence.
    public var invocations: [[String]] {
        switch self {
        case .flushDNS:
            [["/usr/bin/dscacheutil", "-flushcache"], ["/usr/bin/killall", "-HUP", "mDNSResponder"]]
        case .freeMemory:
            [["/usr/sbin/purge"]]
        case .reindexSpotlight:
            [["/usr/bin/mdutil", "-E", "/"]]
        case .thinLocalSnapshots:
            [["/usr/bin/tmutil", "thinlocalsnapshots", "/", "999999999999", "4"]]
        case .listBackgroundItems:
            [["/usr/bin/sfltool", "dumpbtm"]]
        case let .bootout(label):
            [["/bin/launchctl", "bootout", "system/\(label)"]]
        case let .moveToTrash(paths, uid):
            paths.map { ["/bin/mv", "-n", $0, Self.trashFolder(uid: uid) + "/"] }
        case let .forgetWiFiNetwork(name, interface):
            [["/usr/sbin/networksetup", "-removepreferredwirelessnetwork", interface, name]]
        }
    }

    /// Checks the free-form parts of the command. The helper refuses anything invalid.
    public func validate(using safetyGuard: SafetyGuard) -> String? {
        switch self {
        case let .bootout(label):
            guard Self.isValidLabel(label), !label.hasPrefix("com.apple.") else { return "Invalid label" }
        case let .moveToTrash(paths, uid):
            guard uid >= 500, !paths.isEmpty else { return "Invalid user" }
            for path in paths {
                if case let .blocked(reason) = safetyGuard.check(URL(filePath: path), policy: .administrator) {
                    return "\(path): \(reason)"
                }
            }
        case let .forgetWiFiNetwork(name, interface):
            guard !name.isEmpty, name.count <= 64, interface.range(of: #"^en[0-9]{1,2}$"#, options: .regularExpression) != nil else {
                return "Invalid network"
            }
        default:
            break
        }
        return nil
    }

    static func isValidLabel(_ label: String) -> Bool {
        label.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,200}$"#, options: .regularExpression) != nil
    }

    static func trashFolder(uid: UInt32) -> String {
        if let entry = getpwuid(uid), let dir = entry.pointee.pw_dir {
            return String(cString: dir) + "/.Trash"
        }
        return "/Users/Shared/.Trash"
    }
}

public struct PrivilegedResult: Codable, Sendable {
    public var exitCode: Int32
    public var output: String

    public init(exitCode: Int32, output: String) {
        self.exitCode = exitCode
        self.output = output
    }

    public var succeeded: Bool { exitCode == 0 }
}

/// XPC interface of the helper. Commands and results travel as JSON to keep the interface tiny.
@objc public protocol ReviveHelperProtocol {
    func run(_ command: Data, withReply reply: @escaping @Sendable (Data) -> Void)
    func version(withReply reply: @escaping @Sendable (String) -> Void)
}

public enum PrivilegedExecution {
    /// Runs the command's invocations in the current process context (root inside the helper).
    public static func execute(_ command: PrivilegedCommand) -> PrivilegedResult {
        var output = ""
        for argv in command.invocations {
            let process = Process()
            process.executableURL = URL(filePath: argv[0])
            process.arguments = Array(argv.dropFirst())
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
            } catch {
                return PrivilegedResult(exitCode: -1, output: output + error.localizedDescription)
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            output += String(decoding: data, as: UTF8.self)
            if process.terminationStatus != 0 {
                return PrivilegedResult(exitCode: process.terminationStatus, output: output)
            }
        }
        return PrivilegedResult(exitCode: 0, output: output)
    }

    /// Shell command line equivalent to the invocations, every argument single-quoted.
    public static func shellScript(for command: PrivilegedCommand) -> String {
        command.invocations
            .map { argv in argv.map(shellQuote).joined(separator: " ") }
            .joined(separator: " && ")
    }

    static func shellQuote(_ argument: String) -> String {
        "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
