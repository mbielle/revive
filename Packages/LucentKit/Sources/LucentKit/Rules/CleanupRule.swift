import Foundation

/// The four groups shown by the Cleanup module.
public enum CleanupCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case systemJunk
    case aiClutter
    case mailAttachments
    case trashBins

    public var id: String { rawValue }
}

/// One declarative cleaning rule, loaded from `Resources/Rules/*.json`.
///
/// `paths` are glob patterns (`*`, `?`, `[...]` per component, `~` for the home folder).
/// Each match becomes one removable item. Contributing a new rule should never need Swift code.
public struct CleanupRule: Codable, Hashable, Sendable, Identifiable {
    public enum Removal: String, Codable, Sendable {
        /// Moved to the Trash, so the user can still restore it.
        case trash
        /// Permanently deleted. Only for items that already are in a Trash.
        case permanent
    }

    public let id: String
    public let category: CleanupCategory
    public let title: LocalizedText
    public let detail: LocalizedText
    public let paths: [String]
    public var exclude: [String]
    /// Pre-checked in the review screen. Rules for data the user may want to keep are opt-in.
    public var selectedByDefault: Bool
    /// Only match items whose content was last modified more than N days ago.
    public var minAgeDays: Int?
    /// When one of these apps is running, its items are left unchecked: the app may be using them.
    public var appBundleIDs: [String]
    public var removal: Removal
    /// SF Symbol shown next to the rule.
    public var symbol: String

    public init(
        id: String, category: CleanupCategory, title: LocalizedText, detail: LocalizedText, paths: [String],
        exclude: [String] = [], selectedByDefault: Bool = true, minAgeDays: Int? = nil,
        appBundleIDs: [String] = [], removal: Removal = .trash, symbol: String = "folder"
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.detail = detail
        self.paths = paths
        self.exclude = exclude
        self.selectedByDefault = selectedByDefault
        self.minAgeDays = minAgeDays
        self.appBundleIDs = appBundleIDs
        self.removal = removal
        self.symbol = symbol
    }

    enum CodingKeys: String, CodingKey {
        case id, category, title, detail, paths, exclude, selectedByDefault, minAgeDays, appBundleIDs, removal, symbol
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        category = try c.decode(CleanupCategory.self, forKey: .category)
        title = try c.decode(LocalizedText.self, forKey: .title)
        detail = try c.decode(LocalizedText.self, forKey: .detail)
        paths = try c.decode([String].self, forKey: .paths)
        exclude = try c.decodeIfPresent([String].self, forKey: .exclude) ?? []
        selectedByDefault = try c.decodeIfPresent(Bool.self, forKey: .selectedByDefault) ?? true
        minAgeDays = try c.decodeIfPresent(Int.self, forKey: .minAgeDays)
        appBundleIDs = try c.decodeIfPresent([String].self, forKey: .appBundleIDs) ?? []
        removal = try c.decodeIfPresent(Removal.self, forKey: .removal) ?? .trash
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "folder"
    }
}

public enum RuleCatalog {
    /// All rules bundled with the app, in file order. Order matters: earlier rules claim
    /// a path first, so specific rules (AI apps) must come before broad ones (all caches).
    public static func bundled() throws -> [CleanupRule] {
        let files = ["ai-clutter", "system-junk", "mail-attachments", "trash-bins"]
        return try files.flatMap { name -> [CleanupRule] in
            guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Rules") else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "Rules/\(name).json"])
            }
            return try JSONDecoder().decode([CleanupRule].self, from: Data(contentsOf: url))
        }
    }
}
