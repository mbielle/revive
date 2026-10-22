import Foundation
import Testing
@testable import ReviveKit

@Suite struct AppRemovalPolicyTests {
    let safety = SafetyGuard(home: URL(filePath: "/Users/tester"))

    @Test(arguments: [
        "/Users/tester/Library/Preferences/com.example.app.plist",
        "/Users/tester/Library/Group Containers/ABCDE12345.com.example.app",
        "/Users/tester/Library/LaunchAgents/com.example.app.updater.plist",
        "/Library/LaunchDaemons/com.example.helper.plist",
        "/Library/Application Support/Example",
        "/Library/PrivilegedHelperTools/com.example.helper",
    ])
    func allowsAppData(_ path: String) {
        #expect(safety.check(URL(filePath: path), policy: .appRemoval).isAllowed, "\(path)")
        // ...but never for automatic cleanups.
        #expect(!safety.check(URL(filePath: path), policy: .automatic).isAllowed, "\(path)")
    }

    @Test(arguments: [
        "/Users/tester/Library/Preferences/com.apple.finder.plist",
        "/Users/tester/Library/Containers/com.apple.mail",
        "/Users/tester/Library/Keychains/login.keychain-db",
        "/Users/tester/Library/Preferences",
        "/Library/LaunchDaemons/com.apple.something.plist",
        "/Library/Application Support/Apple",
        "/Library/Keychains/System.keychain",
        "/Library/LaunchDaemons",
        "/System/Applications/Mail.app",
        "/Applications/Example.app/Contents/MacOS/Example",
        "/usr/local/bin/tool",
    ])
    func refusesSystemAndAppleData(_ path: String) {
        #expect(!safety.check(URL(filePath: path), policy: .appRemoval).isAllowed, "\(path)")
    }

    @Test func appleAppsCannotBeUninstalled() throws {
        // Safari ships in /Applications but belongs to macOS.
        let safari = URL(filePath: "/Applications/Safari.app")
        if FileManager.default.fileExists(atPath: safari.path(percentEncoded: false)) {
            #expect(!safety.check(safari, policy: .appRemoval).isAllowed)
        }
    }
}

@Suite struct LeftoverFinderTests {
    @Test func matchesBundleIDVariants() {
        let id = "com.example.App"
        for name in ["com.example.app", "com.example.App.plist", "com.example.App.savedState", "TEAM123.com.example.App", "com.example.App.helper"] {
            #expect(LeftoverFinder.name(name, matches: id), "\(name)")
        }
        for name in ["com.example.Application", "com.example.ap", "org.example.App"] {
            #expect(!LeftoverFinder.name(name, matches: id), "\(name)")
        }
    }

    @Test func recognizesBundleIDLikeNames() {
        #expect(LeftoverFinder.bundleIDLike("com.spotify.client.plist") == "com.spotify.client")
        #expect(LeftoverFinder.bundleIDLike("com.foo.bar.savedState") == "com.foo.bar")
        #expect(LeftoverFinder.bundleIDLike("Google") == nil)
        #expect(LeftoverFinder.bundleIDLike("Some Folder.With.Dots") == nil)
    }

    private func makeApp(_ fixture: Fixture, name: String, id: String) throws -> InstalledApp {
        let url = try fixture.file("Applications/\(name).app/Contents/MacOS/\(name)").deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return InstalledApp(url: url, name: name, bundleID: id, version: "1.0", build: "1", size: 0, lastUsed: nil, source: .other, isApple: false)
    }

    @Test func findsAppFilesOnly() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let app = try makeApp(fixture, name: "Example", id: "com.example.app")
        try fixture.file("Library/Preferences/com.example.app.plist")
        try fixture.file("Library/Caches/com.example.app/blob")
        try fixture.file("Library/Application Support/Example/db.sqlite")
        try fixture.file("Library/Containers/com.example.app.widget/data")
        try fixture.file("Library/Preferences/com.example.application.plist")
        try fixture.file("Library/Application Support/Other/db.sqlite")

        var finder = LeftoverFinder(safetyGuard: fixture.safetyGuard)
        finder.systemRoot = fixture.home.appending(path: "nonexistent-system")
        let names = Set(finder.files(for: app).map { $0.url.lastPathComponent })
        #expect(names == ["Example.app", "com.example.app.plist", "com.example.app", "Example", "com.example.app.widget"])
    }

    @Test func orphansSkipInstalledVendorsAndRunningApps() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let chrome = try makeApp(fixture, name: "Chrome", id: "com.google.Chrome")
        try fixture.file("Library/Preferences/com.google.Keystone.Agent.plist")
        try fixture.file("Library/Preferences/com.gone.OldApp.plist")
        try fixture.file("Library/Containers/com.gone.OldApp/data")
        try fixture.file("Library/Preferences/io.running.Tool.plist")
        try fixture.file("Library/Preferences/com.apple.dock.plist")

        let finder = LeftoverFinder(safetyGuard: fixture.safetyGuard)
        let orphans = finder.orphans(installed: [chrome], runningBundleIDs: ["io.running.Tool"]).map { $0.url.lastPathComponent }
        #expect(Set(orphans) == ["com.gone.OldApp.plist", "com.gone.OldApp"])
    }

    @Test func findsInstallers() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.file("Downloads/Setup.dmg")
        try fixture.file("Desktop/Tool.pkg")
        try fixture.file("Downloads/photo.jpg")
        let names = LeftoverFinder(safetyGuard: fixture.safetyGuard).installers().map { $0.url.lastPathComponent }
        #expect(Set(names) == ["Setup.dmg", "Tool.pkg"])
    }
}

@Suite struct UpdateParsingTests {
    @Test func comparesVersions() {
        #expect(Version.compare("1.10", "1.9") == .orderedDescending)
        #expect(Version.compare("2.0", "2.0.0") == .orderedSame)
        #expect(Version.compare("3.1.2 (456)", "3.1.10") == .orderedAscending)
        #expect(Version.compare("120.0.6099.71", "119.9") == .orderedDescending)
    }

    @Test func parsesAppcast() {
        let xml = """
        <?xml version="1.0"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel>
          <item><title>2.1</title><sparkle:version>210</sparkle:version><sparkle:shortVersionString>2.1</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
            <enclosure url="https://example.com/App-2.1.zip" length="1"/></item>
          <item><title>2.0</title><enclosure url="https://example.com/App-2.0.zip" sparkle:version="200" sparkle:shortVersionString="2.0"/></item>
        </channel></rss>
        """
        let items = AppcastParser.parse(Data(xml.utf8))
        #expect(items.count == 2)
        #expect(items[0].version == "210")
        #expect(items[0].shortVersion == "2.1")
        #expect(items[0].minimumSystemVersion == "13.0")
        #expect(items[1].version == "200")
        #expect(items[1].download?.absoluteString == "https://example.com/App-2.0.zip")
    }
}

@Suite struct PerformanceParsingTests {
    @Test func parsesBackgroundTaskDump() {
        let dump = """
        ========================
         Records for UID 501 : 1A2B
        ========================

         ServiceManagement migrated: true

         Items:

         #1:
                         UUID: 11111111-2222
                         Name: Dropbox
               Developer Name: Dropbox, Inc.
                         Type: app (0x2)
                  Disposition: [enabled, allowed, visible, notified] (0xb)
                   Identifier: 2.com.getdropbox.dropbox
                          URL: file:///Applications/Dropbox.app/
            Bundle Identifier: com.getdropbox.dropbox

         #2:
                         UUID: 33333333-4444
                         Name: Updater
               Developer Name: Example Corp
                         Type: legacy daemon (0x10010)
                  Disposition: [disabled, allowed, visible, notified] (0xa)
                   Identifier: 16.com.example.updater
                          URL: file:///Library/LaunchDaemons/com.example.updater.plist
              Executable Path: /Library/Example/updater

         #3:
                         UUID: 55555555
                         Name: Apple thing
                         Type: agent (0x8)
                  Disposition: [enabled, allowed, visible, notified] (0xb)
                   Identifier: 8.com.apple.something
            Bundle Identifier: com.apple.something
        """
        let items = BackgroundTaskDump.parse(dump)
        #expect(items.map(\.name) == ["Dropbox", "Updater"])
        #expect(items[0].isLoginItem && items[0].isEnabled)
        #expect(items[0].developer == "Dropbox, Inc.")
        #expect(!items[1].isLoginItem && !items[1].isEnabled)
        #expect(items[1].executablePath == "/Library/Example/updater")
    }

    @Test func parsesProcessList() {
        let ps = """
          123  12,5 204800 /Applications/Safari.app/Contents/MacOS/Safari
            1   0.3  10240 /sbin/launchd
          456  55.0 512000 /usr/local/bin/some tool with spaces
        """
        let processes = SystemMetrics.parseProcesses(ps)
        #expect(processes.map(\.pid) == [456, 123, 1])
        #expect(processes[0].name == "some tool with spaces")
        #expect(processes[1].memory == 204_800 * 1024)
    }

    @Test func metricsAreReadable() {
        #expect((SystemMetrics.memory()?.total ?? 0) > 0)
        #expect(SystemMetrics.cpuTicks() != nil)
    }
}

@Suite struct PrivilegedCommandTests {
    let safety = SafetyGuard(home: URL(filePath: "/Users/tester"))

    @Test func validatesFreeFormInput() {
        #expect(PrivilegedCommand.bootout(label: "com.example.helper").validate(using: safety) == nil)
        #expect(PrivilegedCommand.bootout(label: "com.apple.mDNSResponder").validate(using: safety) != nil)
        #expect(PrivilegedCommand.bootout(label: "x; rm -rf /").validate(using: safety) != nil)
        #expect(PrivilegedCommand.moveToTrash(paths: ["/Library/LaunchDaemons/com.example.helper.plist"], uid: 501).validate(using: safety) == nil)
        #expect(PrivilegedCommand.moveToTrash(paths: ["/System/Library/CoreServices"], uid: 501).validate(using: safety) != nil)
        #expect(PrivilegedCommand.moveToTrash(paths: ["/Library/LaunchDaemons/com.example.plist"], uid: 0).validate(using: safety) != nil)
        #expect(PrivilegedCommand.forgetWiFiNetwork(name: "Home", interface: "en0").validate(using: safety) == nil)
        #expect(PrivilegedCommand.forgetWiFiNetwork(name: "Home", interface: "en0; reboot").validate(using: safety) != nil)
    }

    @Test func quotesShellArguments() {
        let script = PrivilegedExecution.shellScript(for: .forgetWiFiNetwork(name: "Bob's \"Wi-Fi\" $(reboot)", interface: "en0"))
        #expect(script == #"'/usr/sbin/networksetup' '-removepreferredwirelessnetwork' 'en0' 'Bob'\''s "Wi-Fi" $(reboot)'"#)
    }

    @Test func commandsRoundTripAsJSON() throws {
        let command = PrivilegedCommand.moveToTrash(paths: ["/Library/Caches/com.x"], uid: 501)
        let decoded = try JSONDecoder().decode(PrivilegedCommand.self, from: JSONEncoder().encode(command))
        #expect(decoded == command)
    }
}

@Suite struct MetricsTests {
    @Test func memoryMatchesActivityMonitorDefinition() throws {
        let memory = try #require(SystemMetrics.memory())
        #expect(memory.used > memory.wired)
        #expect(memory.used < memory.total)
    }

    @Test func gpuUsageIsAFraction() {
        if let gpu = SystemMetrics.gpuUsage() { #expect((0...1).contains(gpu)) }
    }
}
