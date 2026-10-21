import Foundation

/// A short piece of user-facing text that ships inside data files (rules, catalogs)
/// rather than in the app's string catalog. English is mandatory, other languages optional.
public struct LocalizedText: Codable, Hashable, Sendable {
    public var en: String
    public var fr: String?

    public init(en: String, fr: String? = nil) {
        self.en = en
        self.fr = fr
    }

    /// The text in the language the app is currently running in.
    public var resolved: String {
        switch LocalizedText.currentLanguage {
        case "fr": fr ?? en
        default: en
        }
    }

    /// Language code of the running app, e.g. "en" or "fr".
    public static var currentLanguage: String {
        Bundle.main.preferredLocalizations.first.map { String($0.prefix(2)) } ?? "en"
    }
}
