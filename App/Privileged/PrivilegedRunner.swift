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

    /// The launchd plist is embedded in Contents/Library/LaunchDaemons.
    static var isBundled: Bool {
        let plist = Bundle.main.bundleURL.appending(path: "Contents/Library/LaunchDaemons/\(helperServiceName).plist")
        return FileManager.default.fileExists(atPath: plist.path(percentEncoded: false))
    }

    private var service: SMAppService { SMAppService.daemon(plistName: "\(helperServiceName).plist") }

    init() {
        refresh()
    }

    func refresh() {
        helperState = switch service.status {
        case .enabled: .enabled
        case .requiresApproval: .needsApproval
        // Before the first registration macOS reports `.notFound` even though the daemon ships
        // in the bundle: only a missing plist means this build cannot install it.
        case .notRegistered, .notFound: Self.isBundled ? .notInstalled : .unavailable
        @unknown default: .unavailable
        }
        #if DEBUG
        NSLog("Lucent helper state: %@", String(describing: helperState))
        #endif
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
        await HelperClient.run(command, connection: HelperClient.systemConnection())
    }

    // MARK: Password prompt

    private func runWithPasswordPrompt(_ commands: [PrivilegedCommand]) async -> PrivilegedResult {
        for command in commands {
            if let problem = command.validate(using: SafetyGuard()) {
                return PrivilegedResult(exitCode: -2, output: "Refused: \(problem)")
            }
        }
        let script = PrivilegedExecution.appleScript(for: commands, prompt: String(localized: "Lucent needs administrator rights for this task."))

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
