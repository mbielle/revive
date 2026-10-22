import AppKit

/// Offers to move Revive into /Applications when it runs from the disk image or from a
/// quarantined download (App Translocation). Each copy outside /Applications needs its own
/// "Open Anyway" approval, keeps no permissions and cannot update itself.
@MainActor
enum ApplicationMover {
    static func offerIfNeeded() {
        #if DEBUG
        return
        #else
        let running = Bundle.main.bundleURL
        guard let source = originalLocation(of: running), needsMove(source) else { return }

        let alert = NSAlert()
        alert.messageText = String(localized: "Move Revive to the Applications folder?")
        alert.informativeText = String(localized: "Revive is running from a disk image or the Downloads folder. In Applications, macOS keeps its permissions and Revive can update itself.")
        alert.addButton(withTitle: String(localized: "Move to Applications"))
        alert.addButton(withTitle: String(localized: "Not Now"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try move(from: source)
        } catch {
            let failure = NSAlert(error: error)
            failure.messageText = String(localized: "Revive could not be moved to Applications.")
            failure.informativeText = String(localized: "Drag Revive to the Applications folder in the Finder, then open it from there.")
            failure.runModal()
        }
        #endif
    }

    static let destination = URL(filePath: "/Applications/Revive.app")

    static func needsMove(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return !path.hasPrefix("/Applications/") && !path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path + "/Applications/")
    }

    private static func move(from source: URL) throws {
        let fileManager = FileManager.default
        let fromDiskImage = source.path.hasPrefix("/Volumes/")
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.trashItem(at: destination, resultingItemURL: nil)
        }
        if fromDiskImage {
            try fileManager.copyItem(at: source, to: destination)
        } else {
            try fileManager.moveItem(at: source, to: destination)
        }
        // The user already approved this copy of Revive when opening it.
        _ = run("/usr/bin/xattr", ["-d", "-r", "com.apple.quarantine", destination.path])

        // Reopen from Applications once this process has quit, then eject the disk image.
        var script = "while /bin/kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \(quoted(destination.path))"
        if fromDiskImage {
            let volume = source.pathComponents.prefix(3).joined(separator: "/").replacingOccurrences(of: "//", with: "/")
            script += "; /usr/bin/hdiutil detach \(quoted(volume)) -quiet"
        }
        let relaunch = Process()
        relaunch.executableURL = URL(filePath: "/bin/sh")
        relaunch.arguments = ["-c", script]
        try relaunch.run()
        NSApp.terminate(nil)
    }

    /// Where the app really is when macOS runs it from a randomized read-only path.
    private static func originalLocation(of url: URL) -> URL? {
        guard url.path.contains("/AppTranslocation/") else { return url }
        typealias OriginalPath = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        guard let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let symbol = dlsym(handle, "SecTranslocateCreateOriginalPathForURL") else { return nil }
        let original = unsafeBitCast(symbol, to: OriginalPath.self)
        return original(url as CFURL, nil)?.takeRetainedValue() as URL?
    }

    private static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func run(_ tool: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        guard (try? process.run()) != nil else { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
