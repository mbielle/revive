import SwiftUI

/// Every entry of the sidebar, with the copy and visuals of its landing screen.
enum AppModule: String, CaseIterable, Identifiable {
    case smartCare, cleanup, protection, performance, applications, myClutter, spaceLens, cloudCleanup
    case myTools, myActivity

    var id: String { rawValue }

    static let mainModules: [AppModule] = [.smartCare, .cleanup, .protection, .performance, .applications, .myClutter, .spaceLens, .cloudCleanup]
    static let footerModules: [AppModule] = [.myTools, .myActivity]

    struct Feature: Identifiable {
        var id: String { symbol }
        let symbol: String
        let title: LocalizedStringResource
    }

    var title: LocalizedStringResource {
        switch self {
        case .smartCare: "Smart Care"
        case .cleanup: "Cleanup"
        case .protection: "Protection"
        case .performance: "Performance"
        case .applications: "Applications"
        case .myClutter: "My Clutter"
        case .spaceLens: "Space Lens"
        case .cloudCleanup: "Cloud Cleanup"
        case .myTools: "My Tools"
        case .myActivity: "My Activity"
        }
    }

    /// Big title of the landing screen, when it differs from the sidebar label.
    var headline: LocalizedStringResource {
        switch self {
        case .cleanup: "Junk Cleanup"
        default: title
        }
    }

    var subtitle: LocalizedStringResource {
        switch self {
        case .smartCare: "Quick maintenance that takes care of the essentials."
        case .cleanup: "Clean your system to achieve maximum performance and reclaim more free space."
        case .protection: "Check your Mac for all kinds of threats and vulnerabilities."
        case .performance: "Keep your Mac in top shape with recommended maintenance."
        case .applications: "Remove apps completely, keep them up to date and get rid of their leftovers."
        case .myClutter: "Find duplicates, similar photos and large forgotten files."
        case .spaceLens: "Get a visual map of your storage and decide what deserves the space."
        case .cloudCleanup: "See what fills your cloud storage and free up local copies."
        case .myTools: "Pin the tools you use the most and launch them in one click."
        case .myActivity: "Everything your Mac got rid of, in one place."
        }
    }

    var symbol: String {
        switch self {
        case .smartCare: "desktopcomputer"
        case .cleanup: "bubbles.and.sparkles.fill"
        case .protection: "hand.raised.fill"
        case .performance: "bolt.fill"
        case .applications: "square.stack.3d.up.fill"
        case .myClutter: "folder.fill"
        case .spaceLens: "circle.hexagongrid.fill"
        case .cloudCleanup: "cloud.fill"
        case .myTools: "square.grid.2x2.fill"
        case .myActivity: "chart.line.uptrend.xyaxis"
        }
    }

    var features: [Feature] {
        switch self {
        case .smartCare: [
            .init(symbol: "clock.arrow.circlepath", title: "Quick Scan"),
            .init(symbol: "gearshape.fill", title: "System Tune-up"),
            .init(symbol: "checkmark.shield.fill", title: "Security Check"),
        ]
        case .cleanup: [
            .init(symbol: "xmark.bin.fill", title: "System Junk"),
            .init(symbol: "sparkles", title: "AI Clutter"),
            .init(symbol: "envelope.fill", title: "Mail Attachments"),
            .init(symbol: "trash.fill", title: "Trash Bins"),
        ]
        case .protection: [
            .init(symbol: "ladybug.fill", title: "Malware Removal"),
            .init(symbol: "lock.shield.fill", title: "Privacy Check"),
            .init(symbol: "lock.open.fill", title: "Application Permissions"),
        ]
        case .performance: [
            .init(symbol: "wrench.and.screwdriver.fill", title: "Maintenance Tasks"),
            .init(symbol: "power", title: "Login Items"),
            .init(symbol: "gearshape.2.fill", title: "Background Items"),
        ]
        case .applications: [
            .init(symbol: "xmark.app.fill", title: "Uninstaller"),
            .init(symbol: "arrow.down.app.fill", title: "Updater"),
            .init(symbol: "puzzlepiece.extension.fill", title: "Leftovers"),
        ]
        case .myClutter: [
            .init(symbol: "doc.on.doc.fill", title: "Duplicates"),
            .init(symbol: "photo.on.rectangle.angled", title: "Similar Photos"),
            .init(symbol: "shippingbox.fill", title: "Large & Old Files"),
        ]
        case .spaceLens: [
            .init(symbol: "circle.hexagongrid.fill", title: "Storage Map"),
            .init(symbol: "magnifyingglass", title: "Find Space Hogs"),
            .init(symbol: "trash.fill", title: "Remove Safely"),
        ]
        case .cloudCleanup: [
            .init(symbol: "icloud.fill", title: "iCloud Drive"),
            .init(symbol: "externaldrive.fill.badge.icloud", title: "Google Drive & OneDrive"),
            .init(symbol: "arrow.down.circle.fill", title: "Local Copies"),
        ]
        case .myTools, .myActivity: []
        }
    }

    var hero: HeroStyle {
        switch self {
        case .smartCare: .monitor
        case .cleanup: .disc
        case .protection: .octagon
        case .performance: .chevron
        case .applications: .squircle
        case .myClutter: .folder
        case .spaceLens: .lens
        case .cloudCleanup: .cloud
        case .myTools: .squircle
        case .myActivity: .disc
        }
    }

    var theme: ModuleTheme {
        switch self {
        case .smartCare: .init(light: 0x9B2FC9, dark: 0x2A0B66, glow: 0xE548D8, button: 0xC81BD8)
        case .cleanup: .init(light: 0x47B83F, dark: 0x0A4A15, glow: 0x8BEA75, button: 0x2E9E35)
        case .protection: .init(light: 0xB0179A, dark: 0x5E0A40, glow: 0xFF62CF, button: 0xE01CB8)
        case .performance: .init(light: 0xE0761F, dark: 0x6E1C05, glow: 0xFFAE4D, button: 0xE57A17)
        case .applications: .init(light: 0x2F78F0, dark: 0x0C1D5E, glow: 0x6FB4FF, button: 0x2A6EF0)
        case .myClutter: .init(light: 0x14A7A0, dark: 0x053C47, glow: 0x5FE8D9, button: 0x0FA197)
        case .spaceLens: .init(light: 0x5D4FE6, dark: 0x1A0F5E, glow: 0x9C8CFF, button: 0x6A55F2)
        case .cloudCleanup: .init(light: 0x2C9DEB, dark: 0x0B3A6E, glow: 0x7FD0FF, button: 0x1E8FE6)
        case .myTools: .init(light: 0xD23A6E, dark: 0x4A0C2C, glow: 0xFF7FA6, button: 0xE0457A)
        case .myActivity: .init(light: 0x4C5B7A, dark: 0x141B2D, glow: 0x8EA2CC, button: 0x5B6E96)
        }
    }
}
