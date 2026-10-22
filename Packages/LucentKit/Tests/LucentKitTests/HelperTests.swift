import Foundation
import Testing
@testable import LucentKit

/// Exercises the helper's real XPC code path with an in-process anonymous listener.
/// Commands are recorded instead of executed, so nothing runs as root.
@Suite(.serialized) struct HelperXPCTests {
    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var commands: [PrivilegedCommand] = []
        func append(_ command: PrivilegedCommand) { lock.lock(); commands.append(command); lock.unlock() }
        var all: [PrivilegedCommand] { lock.lock(); defer { lock.unlock() }; return commands }
    }

    func makeListener(requirement: String?, recorder: Recorder) -> (NSXPCListener, HelperListenerDelegate) {
        let delegate = HelperListenerDelegate(requirement: requirement) {
            HelperService(home: { URL(filePath: "/Users/tester") }) { command in
                recorder.append(command)
                return PrivilegedResult(exitCode: 0, output: "ran \(command)")
            }
        }
        let listener = NSXPCListener.anonymous()
        listener.delegate = delegate
        listener.resume()
        return (listener, delegate)
    }

    @Test func runsValidCommandsThroughXPC() async throws {
        let recorder = Recorder()
        let (listener, delegate) = makeListener(requirement: "", recorder: recorder)
        defer { listener.invalidate(); _ = delegate }

        let result = await HelperClient.run(.flushDNS, connection: NSXPCConnection(listenerEndpoint: listener.endpoint))
        #expect(result?.succeeded == true)
        #expect(recorder.all == [.flushDNS])

        let trash = PrivilegedCommand.moveToTrash(paths: ["/Library/LaunchDaemons/com.example.helper.plist"], uid: 501)
        let moved = await HelperClient.run(trash, connection: NSXPCConnection(listenerEndpoint: listener.endpoint))
        #expect(moved?.succeeded == true)
        #expect(recorder.all.last == trash)
    }

    @Test func refusesDangerousCommandsBeforeRunningThem() async throws {
        let recorder = Recorder()
        let (listener, delegate) = makeListener(requirement: "", recorder: recorder)
        defer { listener.invalidate(); _ = delegate }

        for command in [
            PrivilegedCommand.moveToTrash(paths: ["/System/Library/CoreServices/Finder.app"], uid: 501),
            .moveToTrash(paths: ["/Users/tester/Documents"], uid: 501),
            .bootout(label: "com.apple.mDNSResponder"),
            .forgetWiFiNetwork(name: "x", interface: "en0; reboot"),
        ] {
            let result = await HelperClient.run(command, connection: NSXPCConnection(listenerEndpoint: listener.endpoint))
            #expect(result?.exitCode == -2, "\(command) must be refused")
        }
        #expect(recorder.all.isEmpty)
    }

    @Test func rejectsClientsThatAreNotLucent() async throws {
        let recorder = Recorder()
        // The test runner is not signed as io.github.mbielle.Lucent: the connection must fail.
        let (listener, delegate) = makeListener(requirement: "identifier \"io.github.mbielle.Lucent\"", recorder: recorder)
        defer { listener.invalidate(); _ = delegate }

        let result = await HelperClient.run(.freeMemory, connection: NSXPCConnection(listenerEndpoint: listener.endpoint))
        #expect(result == nil)
        #expect(recorder.all.isEmpty)
    }

    @Test func refusesEveryoneWithoutRequirement() async throws {
        let recorder = Recorder()
        let (listener, delegate) = makeListener(requirement: nil, recorder: recorder)
        defer { listener.invalidate(); _ = delegate }

        let result = await HelperClient.run(.freeMemory, connection: NSXPCConnection(listenerEndpoint: listener.endpoint))
        #expect(result == nil)
    }

    @Test func releaseHelperWithoutTeamAcceptsNobody() {
        // Test binaries are ad-hoc signed (no team): a release helper would refuse all clients.
        #expect(HelperListenerDelegate.requirement(allowsAdHoc: false) == nil)
        #expect(HelperListenerDelegate.requirement(allowsAdHoc: true) == "identifier \"io.github.mbielle.Lucent\"")
    }
}

@Suite struct PasswordPromptTests {
    @Test @MainActor func generatedAppleScriptCompiles() throws {
        let commands: [PrivilegedCommand] = [
            .freeMemory, .flushDNS,
            .moveToTrash(paths: [#"/Library/Application Support/Weird "Name" \ App"#], uid: 501),
            .forgetWiFiNetwork(name: #"Café "Wi-Fi" $(reboot) 'x'"#, interface: "en0"),
        ]
        let source = PrivilegedExecution.appleScript(for: commands, prompt: "Lucent a besoin des droits « administrateur ».")
        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        #expect(script?.compileAndReturnError(&error) == true, "\(error ?? [:])")
        #expect(source.contains("with administrator privileges"))
    }

    @Test func shellQuotingSurvivesTheRoundTrip() throws {
        // What `do shell script` will execute, once AppleScript has unescaped the string.
        let command = PrivilegedCommand.forgetWiFiNetwork(name: #"Bob's "net" $(id)"#, interface: "en0")
        let shell = PrivilegedExecution.shellScript(for: command)
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        // Replace the real tool by printf to see the exact arguments it would receive.
        process.arguments = ["-c", shell.replacingOccurrences(of: "'/usr/sbin/networksetup'", with: "printf '[%s]'")]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(output == #"[-removepreferredwirelessnetwork][en0][Bob's "net" $(id)]"#)
    }
}
