import Foundation
import LucentKit
import Security
import SystemConfiguration

/// Lucent's privileged helper. launchd starts it on demand as root when the app connects.
/// It only runs the commands of `PrivilegedCommand`, only for the signed Lucent app.
final class HelperService: NSObject, LucentHelperProtocol {
    func run(_ command: Data, withReply reply: @escaping @Sendable (Data) -> Void) {
        let result: PrivilegedResult
        if let decoded = try? JSONDecoder().decode(PrivilegedCommand.self, from: command) {
            // Validate against the guard of the user who owns the console, not root's home.
            let safety = SafetyGuard(home: consoleUserHome())
            if let problem = decoded.validate(using: safety) {
                result = PrivilegedResult(exitCode: -2, output: "Refused: \(problem)")
            } else {
                result = PrivilegedExecution.execute(decoded)
            }
        } else {
            result = PrivilegedResult(exitCode: -3, output: "Unknown command")
        }
        reply((try? JSONEncoder().encode(result)) ?? Data())
    }

    func version(withReply reply: @escaping @Sendable (String) -> Void) {
        reply(helperVersion)
    }

    private func consoleUserHome() -> URL {
        var uid: uid_t = 0
        if SCDynamicStoreCopyConsoleUser(nil, &uid, nil) != nil, let entry = getpwuid(uid), let dir = entry.pointee.pw_dir {
            return URL(filePath: String(cString: dir))
        }
        return URL(filePath: "/var/empty")
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard let requirement = clientRequirement() else { return false }
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = NSXPCInterface(with: LucentHelperProtocol.self)
        connection.exportedObject = HelperService()
        connection.resume()
        return true
    }

    /// Only the Lucent app signed by the same team as this helper may connect.
    private func clientRequirement() -> String? {
        let identifier = "io.github.mbielle.Lucent"
        if let team = ownTeamIdentifier() {
            return "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
        }
        #if DEBUG
        // Ad-hoc signed development builds have no team: fall back to the identifier.
        return "identifier \"\(identifier)\""
        #else
        return nil
        #endif
    }

    private func ownTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }
}

let helperVersion = "1"
let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: helperServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
