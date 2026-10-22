import Foundation

/// Something the Protection module found.
public struct Threat: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// Matched one of Apple's XProtect malware signatures.
        case malware(signature: String)
        /// Starts automatically but is unsigned or lives somewhere malware likes to hide.
        case suspiciousPersistence(reason: String)
    }

    public var id: String { url.normalizedPath }
    public let url: URL
    public let kind: Kind
    /// Files to remove together with it, e.g. the launchd plist that starts it.
    public let related: [URL]

    public var isMalware: Bool {
        if case .malware = kind { true } else { false }
    }

    public var displayName: String { url.lastPathComponent }
}

/// Looks for malware with XProtect's rules and for suspicious auto-starting programs,
/// the way Objective-See's KnockKnock (GPL-3.0) inspects persistence locations.
public struct ThreatScanner: Sendable {
    public enum Depth: Sendable { case quick, deep }

    public let home: URL
    public var maxFileSize: Int64 = 100_000_000

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    public func scan(depth: Depth, rules: YaraRules?, progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }) async -> [Threat] {
        var threats: [Threat] = []
        let launchItems = LaunchItemScanner(home: home).scan()
        threats += persistenceFindings(launchItems)

        guard let rules else { return threats }
        let targets = filesToScan(depth: depth, launchItems: launchItems)
        let flagged = Set(threats.map(\.id))
        var done = 0
        for target in targets {
            if Task.isCancelled { break }
            done += 1
            if done % 25 == 0 || done == targets.count {
                progress(ScanProgress(currentPath: target.path(percentEncoded: false), bytesFound: 0,
                                      fraction: Double(done) / Double(max(targets.count, 1)), itemCount: done))
            }
            let matches = rules.scan(target)
            guard let signature = matches.first, !flagged.contains(target.normalizedPath) else { continue }
            let plist = launchItems.first { $0.program == target.path(percentEncoded: false) }?.plist
            threats.removeAll { $0.id == target.normalizedPath }
            threats.append(Threat(url: target, kind: .malware(signature: signature), related: plist.map { [$0] } ?? []))
        }
        return threats.sorted { $0.isMalware && !$1.isMalware }
    }

    // MARK: Persistence

    /// Folders where legitimate software rarely installs auto-starting programs.
    static let suspiciousLocations = ["/tmp/", "/private/tmp/", "/private/var/tmp/", "/Users/Shared/", "/var/folders/"]

    func persistenceFindings(_ items: [LaunchItem]) -> [Threat] {
        items.compactMap { item in
            guard let program = item.program, program.hasPrefix("/") else { return nil }
            let url = URL(filePath: program)
            guard FileManager.default.fileExists(atPath: program) else { return nil }
            if Self.suspiciousLocations.contains(where: { program.hasPrefix($0) }) || url.pathComponents.contains(where: { $0.hasPrefix(".") && $0.count > 1 }) {
                return Threat(url: url, kind: .suspiciousPersistence(reason: "Runs from a hidden or temporary folder"), related: [item.plist])
            }
            let info = CodeSignature.info(ofPath: program)
            if !info.isSigned, Self.isMachO(url) {
                return Threat(url: url, kind: .suspiciousPersistence(reason: "Unsigned program that starts automatically"), related: [item.plist])
            }
            return nil
        }
    }

    // MARK: Targets

    func filesToScan(depth: Depth, launchItems: [LaunchItem]) -> [URL] {
        var files: [URL] = launchItems.compactMap { $0.program.map { URL(filePath: $0) } }
        files += AppInventory.appBundles(in: URL(filePath: "/Applications")).compactMap(Self.mainExecutable)
        files += AppInventory.appBundles(in: home.appending(path: "Applications")).compactMap(Self.mainExecutable)
        files += candidates(in: home.appending(path: "Downloads"), maxDepth: depth == .quick ? 2 : 6)
        files += candidates(in: home.appending(path: "Desktop"), maxDepth: depth == .quick ? 1 : 4)
        if depth == .deep {
            files += candidates(in: home.appending(path: "Documents"), maxDepth: 5)
            files += candidates(in: home.appending(path: "Library/Application Support"), maxDepth: 4)
            files += candidates(in: URL(filePath: "/Users/Shared"), maxDepth: 4)
            files += candidates(in: URL(filePath: "/Library/Application Support"), maxDepth: 3)
        }
        var seen = Set<String>()
        return files.filter { seen.insert($0.normalizedPath).inserted && FileManager.default.isReadableFile(atPath: $0.path(percentEncoded: false)) }
    }

    static func mainExecutable(_ app: URL) -> URL? {
        Bundle(url: app)?.executableURL
    }

    /// Executables, scripts and app bundles below `folder`.
    func candidates(in folder: URL, maxDepth: Int) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isPackageKey],
            options: [], errorHandler: { _, _ in true }
        ) else { return [] }
        let scriptExtensions: Set<String> = ["sh", "command", "py", "pl", "rb", "js", "scpt", "applescript", "jar", "bash", "zsh", "dylib", "so", "pkg"]
        var result: [URL] = []
        let baseDepth = folder.pathComponents.count
        for case let url as URL in enumerator {
            if url.pathComponents.count - baseDepth > maxDepth { enumerator.skipDescendants(); continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isPackageKey])
            if values?.isPackage == true, url.pathExtension == "app" {
                if let executable = Self.mainExecutable(url) { result.append(executable) }
                enumerator.skipDescendants()
                continue
            }
            guard values?.isRegularFile == true, Int64(values?.fileSize ?? 0) <= maxFileSize else { continue }
            if scriptExtensions.contains(url.pathExtension.lowercased()) || Self.isMachO(url) || Self.hasShebang(url) {
                result.append(url)
            }
        }
        return result
    }

    static func isMachO(_ url: URL) -> Bool {
        guard let magic = readPrefix(url, count: 4), magic.count == 4 else { return false }
        let value = magic.withUnsafeBytes { $0.load(as: UInt32.self) }
        return [0xFEEDFACE, 0xFEEDFACF, 0xCEFAEDFE, 0xCFFAEDFE, 0xCAFEBABE, 0xBEBAFECA].contains(value)
    }

    static func hasShebang(_ url: URL) -> Bool {
        readPrefix(url, count: 2) == Data("#!".utf8)
    }

    private static func readPrefix(_ url: URL, count: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: count)
    }
}
