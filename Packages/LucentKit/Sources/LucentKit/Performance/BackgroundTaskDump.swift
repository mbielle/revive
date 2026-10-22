import Foundation

/// An entry of macOS's Background Task Management database (System Settings › Login Items).
public struct BackgroundTaskItem: Identifiable, Hashable, Sendable {
    public var id: String { uuid ?? "\(identifier ?? name)-\(executablePath ?? "")" }
    public var uuid: String?
    public var name: String
    public var developer: String?
    public var type: String
    public var isEnabled: Bool
    public var identifier: String?
    public var bundleID: String?
    public var url: String?
    public var executablePath: String?
    public var parentIdentifier: String?

    /// Apps and login items the user opens at login, as opposed to agents and daemons.
    public var isLoginItem: Bool {
        type.contains("app") || type.contains("login item")
    }
}

/// Parses the text printed by `sfltool dumpbtm`.
public enum BackgroundTaskDump {
    public static func parse(_ text: String) -> [BackgroundTaskItem] {
        var items: [BackgroundTaskItem] = []
        var fields: [String: String] = [:]

        func flush() {
            defer { fields = [:] }
            guard let name = fields["Name"], let type = fields["Type"] else { return }
            let disposition = fields["Disposition"] ?? ""
            let item = BackgroundTaskItem(
                uuid: fields["UUID"],
                name: name == "(null)" ? (fields["Identifier"] ?? name) : name,
                developer: fields["Developer Name"].flatMap { $0 == "(null)" ? nil : $0 },
                type: type.components(separatedBy: " (").first ?? type,
                isEnabled: disposition.contains("enabled") && !disposition.contains("disabled"),
                identifier: fields["Identifier"],
                bundleID: fields["Bundle Identifier"],
                url: fields["URL"].flatMap { $0 == "(null)" ? nil : $0 },
                executablePath: fields["Executable Path"],
                parentIdentifier: fields["Parent Identifier"]
            )
            if !(item.bundleID ?? item.identifier ?? "").contains("com.apple.") {
                items.append(item)
            }
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#"), line.hasSuffix(":") {
                flush()
                continue
            }
            if line.hasPrefix("====") || line.hasPrefix("Records for") {
                flush()
                continue
            }
            guard let colon = line.range(of: ": ") else { continue }
            let key = String(line[..<colon.lowerBound])
            let value = String(line[colon.upperBound...])
            if fields[key] == nil { fields[key] = value }
        }
        flush()

        // The same item is listed once per user record; keep one.
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }
}
