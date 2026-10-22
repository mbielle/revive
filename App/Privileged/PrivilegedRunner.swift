import AppKit
import LucentKit
import ServiceManagement

/// Runs administrator commands through the privileged helper when it is installed, or by
/// asking for the administrator password (macOS's own prompt) when it is not.
@MainActor @Observable
final class PrivilegedRunner {
    enum HelperState: Equatable {
        case notInstalled, needsApproval, enabled, unavailable
    }

    private(set) var helperState: HelperState = .notInstalled
    private(set) var lastError: String?

    private var service: SMAppService { SMAppService.daemon(plistName: "\(helperServiceName).plist") }

    init() {
        refresh()
    }

    func refresh() {
        helperState = switch service.status {
        case .enabled: .enabled
        case .requiresApproval: .needsApproval
        case .notRegistered: .notInstalled
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    /// Registers the helper. macOS then asks the user to allow it in System Settings › Login Items.
    func installHelper() {
        do {
            try service.register()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
        if helperState == .needsApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    func uninstallHelper() async {
        try? await service.unregister()
        refresh()
    }

    func run(_ command: PrivilegedCommand) async -> PrivilegedResult {
        await run([command])
    }

    /// Runs several commands; without the helper they share a single password prompt.
    func run(_ commands: [PrivilegedCommand]) async -> PrivilegedResult {
        guard !commands.isEmpty else { return PrivilegedResult(exitCode: 0, output: "") }
        refresh()
        if helperState == .enabled {
            var output = ""
            var failed: Int32 = 0
            for command in commands {
                guard let result = await runWithHelper(command) else { return await runWithPasswordPrompt(commands) }
                output += result.output
                if !result.succeeded { failed = result.exitCode }
            }
            return PrivilegedResult(exitCode: failed, output: output)
        }
        return await runWithPasswordPrompt(commands)
    }

    // MARK: Helper

    private func runWithHelper(_ command: PrivilegedCommand) async -> PrivilegedResult? {
        guard let payload = try? JSONEncoder().encode(command) else { return nil }
        let connection = NSXPCConnection(machServiceName: helperServiceName, options: .privileged)
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
            let c = continuation
            continuation = nil
            lock.unlock()
            c?.resume(returning: value)
        }
    }

    // MARK: Password prompt

    private func runWithPasswordPrompt(_ commands: [PrivilegedCommand]) async -> PrivilegedResult {
        for command in commands {
            if let problem = command.validate(using: SafetyGuard()) {
                return PrivilegedResult(exitCode: -2, output: "Refused: \(problem)")
            }
        }
        // Each command runs even if a previous one failed; the last status is reported.
        let shell = commands.map { "(" + PrivilegedExecution.shellScript(for: $0) + ")" }.joined(separator: "; ")
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let prompt = String(localized: "Lucent needs administrator rights for this task.")
        let script = "do shell script \"\(escaped)\" with prompt \"\(prompt)\" with administrator privileges"

        return await Task.detached {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do { try process.run() } catch { return PrivilegedResult(exitCode: -1, output: error.localizedDescription) }
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            return PrivilegedResult(exitCode: process.terminationStatus, output: output)
        }.value
    }
}
