import CYara
import Foundation

/// Compiled YARA rules, ready to scan files.
///
/// The default rule set is Apple's own XProtect signatures, already installed and kept up to date
/// on every Mac. Lucent reads them in place: it ships no malware database of its own.
public final class YaraRules: @unchecked Sendable {
    public static let xprotectFolder = URL(filePath: "/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Resources")

    private let rules: UnsafeMutablePointer<YR_RULES>
    public let ruleCount: Int
    private let lock = NSLock()

    public enum Failure: Error, Equatable {
        case initialization
        case compilation(String)
        case missingRules
    }

    /// Compiles rule sources. Each entry is (namespace, YARA source text).
    public init(sources: [(String, String)]) throws {
        try YaraRules.initializeLibrary()
        var compiler: UnsafeMutablePointer<YR_COMPILER>?
        guard yr_compiler_create(&compiler) == ERROR_SUCCESS, let compiler else { throw Failure.initialization }
        defer { yr_compiler_destroy(compiler) }

        let errors = ErrorCollector()
        let context = Unmanaged.passUnretained(errors).toOpaque()
        yr_compiler_set_callback(compiler, { level, _, line, _, message, userData in
            guard level == YARA_ERROR_LEVEL_ERROR, let userData, let message else { return }
            let collector = Unmanaged<ErrorCollector>.fromOpaque(userData).takeUnretainedValue()
            collector.messages.append("line \(line): \(String(cString: message))")
        }, context)

        var count = 0
        for (namespace, source) in sources {
            let failures = yr_compiler_add_string(compiler, source, namespace)
            if failures > 0 { throw Failure.compilation(errors.messages.prefix(3).joined(separator: "; ")) }
            count += source.components(separatedBy: "\nrule ").count - 1 + (source.hasPrefix("rule ") ? 1 : 0)
        }

        var compiled: UnsafeMutablePointer<YR_RULES>?
        guard yr_compiler_get_rules(compiler, &compiled) == ERROR_SUCCESS, let compiled else {
            throw Failure.compilation(errors.messages.first ?? "unknown error")
        }
        rules = compiled
        ruleCount = count
    }

    /// Apple's XProtect rules (binaries and scripts).
    public static func xprotect(folder: URL = xprotectFolder) throws -> YaraRules {
        let files = [("xprotect", "XProtect.yara"), ("xpscripts", "XPScripts.yr")]
        let sources = files.compactMap { namespace, name -> (String, String)? in
            guard let text = try? String(contentsOf: folder.appending(path: name), encoding: .utf8) else { return nil }
            return (namespace, text)
        }
        guard !sources.isEmpty else { throw Failure.missingRules }
        return try YaraRules(sources: sources)
    }

    deinit {
        yr_rules_destroy(rules)
    }

    /// Names of the rules matching the file. Empty when the file is clean or unreadable.
    public func scan(_ url: URL, timeout: Int32 = 10) -> [String] {
        let matches = MatchCollector()
        let context = Unmanaged.passUnretained(matches).toOpaque()
        lock.lock()
        defer { lock.unlock() }
        _ = yr_rules_scan_file(rules, url.path(percentEncoded: false), SCAN_FLAGS_FAST_MODE, { _, message, data, userData in
            if message == CALLBACK_MSG_RULE_MATCHING, let data, let userData {
                let rule = data.assumingMemoryBound(to: YR_RULE.self)
                if let identifier = rule.pointee.identifier {
                    Unmanaged<MatchCollector>.fromOpaque(userData).takeUnretainedValue().names.append(String(cString: identifier))
                }
            }
            return CALLBACK_CONTINUE
        }, context, timeout)
        return matches.names
    }

    private final class ErrorCollector { var messages: [String] = [] }
    private final class MatchCollector { var names: [String] = [] }

    private static let initialized: Bool = yr_initialize() == ERROR_SUCCESS

    private static func initializeLibrary() throws {
        guard initialized else { throw Failure.initialization }
    }
}
