import Foundation

/// One-click maintenance scripts of the Performance module.
public enum MaintenanceTask: String, CaseIterable, Sendable, Identifiable, Codable {
    case freeMemory
    case flushDNS
    case rebuildLaunchServices
    case resetQuickLook
    case reindexSpotlight
    case thinTimeMachineSnapshots

    public var id: String { rawValue }

    public var title: LocalizedText {
        switch self {
        case .freeMemory: .init(en: "Free Up RAM", fr: "Libérer la mémoire vive")
        case .flushDNS: .init(en: "Flush DNS Cache", fr: "Vider le cache DNS")
        case .rebuildLaunchServices: .init(en: "Repair \"Open With\" Menu", fr: "Réparer le menu « Ouvrir avec »")
        case .resetQuickLook: .init(en: "Reset Quick Look", fr: "Réinitialiser Coup d'œil")
        case .reindexSpotlight: .init(en: "Reindex Spotlight", fr: "Réindexer Spotlight")
        case .thinTimeMachineSnapshots: .init(en: "Thin Time Machine Snapshots", fr: "Alléger les instantanés Time Machine")
        }
    }

    public var detail: LocalizedText {
        switch self {
        case .freeMemory:
            .init(en: "Clears inactive memory so apps that need it get it faster.",
                  fr: "Libère la mémoire inactive pour que les apps qui en ont besoin l'obtiennent plus vite.")
        case .flushDNS:
            .init(en: "Fixes websites that won't load after a network or DNS change.",
                  fr: "Corrige les sites qui ne se chargent plus après un changement de réseau ou de DNS.")
        case .rebuildLaunchServices:
            .init(en: "Removes duplicate and outdated apps from the \"Open With\" menu.",
                  fr: "Retire les apps en double ou obsolètes du menu « Ouvrir avec ».")
        case .resetQuickLook:
            .init(en: "Fixes blank or wrong file previews and thumbnails.",
                  fr: "Corrige les aperçus et vignettes de fichiers vides ou incorrects.")
        case .reindexSpotlight:
            .init(en: "Rebuilds the search index when Spotlight misses files. Search is slower for a while.",
                  fr: "Reconstruit l'index quand Spotlight ne trouve plus des fichiers. La recherche ralentit un moment.")
        case .thinTimeMachineSnapshots:
            .init(en: "Removes local Time Machine snapshots kept on this disk. Backups on your backup disk stay.",
                  fr: "Supprime les instantanés Time Machine locaux. Les sauvegardes sur votre disque de sauvegarde restent.")
        }
    }

    public var symbol: String {
        switch self {
        case .freeMemory: "memorychip"
        case .flushDNS: "network"
        case .rebuildLaunchServices: "contextualmenu.and.cursorarrow"
        case .resetQuickLook: "eye"
        case .reindexSpotlight: "magnifyingglass"
        case .thinTimeMachineSnapshots: "clock.arrow.circlepath"
        }
    }

    /// Part of the recommended set run by Smart Care and pre-checked in Performance.
    public var isRecommended: Bool {
        switch self {
        case .freeMemory, .flushDNS, .rebuildLaunchServices, .resetQuickLook: true
        case .reindexSpotlight, .thinTimeMachineSnapshots: false
        }
    }

    /// The administrator command, or nil when the task runs as the current user.
    public var privilegedCommand: PrivilegedCommand? {
        switch self {
        case .freeMemory: .freeMemory
        case .flushDNS: .flushDNS
        case .reindexSpotlight: .reindexSpotlight
        case .thinTimeMachineSnapshots: .thinLocalSnapshots
        case .rebuildLaunchServices, .resetQuickLook: nil
        }
    }

    /// Commands for tasks that don't need administrator rights.
    public var userInvocations: [[String]] {
        switch self {
        case .rebuildLaunchServices:
            [["/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
              "-r", "-domain", "local", "-domain", "system", "-domain", "user"]]
        case .resetQuickLook:
            [["/usr/bin/qlmanage", "-r"], ["/usr/bin/qlmanage", "-r", "cache"]]
        default:
            []
        }
    }

    /// Runs a task that needs no administrator rights.
    public func runAsUser() -> PrivilegedResult {
        var output = ""
        for argv in userInvocations {
            let process = Process()
            process.executableURL = URL(filePath: argv[0])
            process.arguments = Array(argv.dropFirst())
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do { try process.run() } catch { return PrivilegedResult(exitCode: -1, output: error.localizedDescription) }
            output += String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            if process.terminationStatus != 0 { return PrivilegedResult(exitCode: process.terminationStatus, output: output) }
        }
        return PrivilegedResult(exitCode: 0, output: output)
    }
}
