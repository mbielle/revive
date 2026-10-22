import Foundation
import Security
import SystemConfiguration

/// The object the privileged helper exports over XPC. Lives in ReviveKit so it can be tested
/// with an in-process listener; the helper executable only wires it to launchd.
public final class HelperService: NSObject, ReviveHelperProtocol, Sendable {
    public static let version = "1"

    /// Home folder whose SafetyGuard validates paths. Defaults to the console user's home.
    private let home: @Sendable () -> URL
    /// Runs a validated command. Replaced in tests so nothing is executed as root.
    private let executor: @Sendable (PrivilegedCommand) -> PrivilegedResult

    public init(home: @escaping @Sendable () -> URL = HelperService.consoleUserHome,
                executor: @escaping @Sendable (PrivilegedCommand) -> PrivilegedResult = PrivilegedExecution.execute) {
        self.home = home
        self.executor = executor
    }

    public func run(_ command: Data, withReply reply: @escaping @Sendable (Data) -> Void) {
        let result: PrivilegedResult
        if let decoded = try? JSONDecoder().decode(PrivilegedCommand.self, from: command) {
            if let problem = decoded.validate(using: SafetyGuard(home: home())) {
                result = PrivilegedResult(exitCode: -2, output: "Refused: \(problem)")
            } else {
                result = executor(decoded)
            }
        } else {
            result = PrivilegedResult(exitCode: -3, output: "Unknown command")
        }
        reply((try? JSONEncoder().encode(result)) ?? Data())
    }

    public func version(withReply reply: @escaping @Sendable (String) -> Void) {
        reply(Self.version)
    }

    /// Home of the user logged in at the screen; root's own home is never used.
    @Sendable public static func consoleUserHome() -> URL {
        var uid: uid_t = 0
        if SCDynamicStoreCopyConsoleUser(nil, &uid, nil) != nil, let entry = getpwuid(uid), let dir = entry.pointee.pw_dir {
            return URL(filePath: String(cString: dir))
        }
        return URL(filePath: "/var/empty")
    }
}

/// Accepts connections from the Revive app only, and exports a `HelperService` to each.
public final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate, Sendable {
    public static let clientIdentifier = "io.github.mbielle.Revive"

    private let requirement: String?
    private let makeService: @Sendable () -> HelperService

    /// `requirement` is the code signing requirement clients must satisfy; nil refuses everyone.
    public init(requirement: String?, makeService: @escaping @Sendable () -> HelperService = { HelperService() }) {
        self.requirement = requirement
        self.makeService = makeService
    }

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard let requirement else { return false }
        if !requirement.isEmpty { connection.setCodeSigningRequirement(requirement) }
        connection.exportedInterface = NSXPCInterface(with: ReviveHelperProtocol.self)
        connection.exportedObject = makeService()
        connection.resume()
        return true
    }

    /// Requirement for the running helper: same team as the helper itself. Ad-hoc signed helpers
    /// have no team; they only accept clients in debug builds (`allowsAdHoc`).
    public static func requirement(allowsAdHoc: Bool) -> String? {
        if let team = ownTeamIdentifier() {
            return "anchor apple generic and identifier \"\(clientIdentifier)\" and certificate leaf[subject.OU] = \"\(team)\""
        }
        return allowsAdHoc ? "identifier \"\(clientIdentifier)\"" : nil
    }

    static func ownTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
