import Foundation

/// Sends commands to the privileged helper over XPC.
public enum HelperClient {
    /// Connection to the installed helper (launchd mach service, privileged).
    public static func systemConnection() -> NSXPCConnection {
        NSXPCConnection(machServiceName: helperServiceName, options: .privileged)
    }

    /// Runs one command. Returns nil when the helper cannot be reached or refuses the connection,
    /// so callers can fall back to the password prompt.
    public static func run(_ command: PrivilegedCommand, connection: NSXPCConnection) async -> PrivilegedResult? {
        guard let payload = try? JSONEncoder().encode(command) else { return nil }
        connection.remoteObjectInterface = NSXPCInterface(with: LucentHelperProtocol.self)
        connection.resume()
        defer { connection.invalidate() }

        return await withCheckedContinuation { continuation in
            let once = Once(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in once.resume(nil) } as? LucentHelperProtocol
            guard let proxy else { return once.resume(nil) }
            proxy.run(payload) { data in
                once.resume(try? JSONDecoder().decode(PrivilegedResult.self, from: data))
            }
        }
    }

    /// Resumes a continuation exactly once, whichever XPC callback fires first.
    private final class Once: @unchecked Sendable {
        private var continuation: CheckedContinuation<PrivilegedResult?, Never>?
        private let lock = NSLock()

        init(_ continuation: CheckedContinuation<PrivilegedResult?, Never>) { self.continuation = continuation }

        func resume(_ value: PrivilegedResult?) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: value)
        }
    }
}

extension PrivilegedExecution {
    /// AppleScript that runs the commands with macOS's administrator password prompt.
    /// Every command runs even if a previous one failed; the last status is reported.
    public static func appleScript(for commands: [PrivilegedCommand], prompt: String) -> String {
        let shell = commands.map { "(" + shellScript(for: $0) + ")" }.joined(separator: "; ")
        return "do shell script \"\(escapeForAppleScript(shell))\" with prompt \"\(escapeForAppleScript(prompt))\" with administrator privileges"
    }

    static func escapeForAppleScript(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
