import ReviveKit
import SwiftUI

struct ProtectionView: View {
    @Bindable var model: ProtectionModel
    private let module = AppModule.protection

    var body: some View {
        Group {
            switch model.phase {
            case .idle:
                ModuleLanding(module: module) {
                    PillPicker(options: [(false, String(localized: "Quick Scan")), (true, String(localized: "Deep Scan"))], selection: $model.deepScan)
                } action: {
                    ScanButton(title: "Scan", theme: module.theme) { model.scan() }
                }
            case .scanning:
                WorkingView(module: module, title: "Checking for threats…", progress: model.progress.fraction,
                            detail: model.progress.currentPath,
                            stat: model.progress.itemCount > 0 ? String(localized: "\(model.progress.itemCount) files checked") : nil) { model.stop() }
            case .ready, .removing:
                switch model.section {
                case nil: overview
                case .malware: MalwareScreen(model: model)
                case .privacy: PrivacyScreen(model: model)
                case .extensions: ExtensionsScreen(model: model)
                case .wifi: WiFiScreen(model: model)
                case .permissions: PermissionsScreen(model: model)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.phase)
        .animation(.easeInOut(duration: 0.3), value: model.section)
    }

    private var overview: some View {
        let malware = model.threats.filter(\.isMalware).count
        let privacySize = model.privacyItems.reduce(0) { $0 + $1.size }
        let appsWithPermissions = Set(model.permissions.filter(\.isAllowed).map(\.client)).count
        return OverviewScreen(
            title: model.threats.isEmpty ? String(localized: "No threats found")
                : model.threats.count == 1 ? String(localized: "1 item needs your attention")
                : String(localized: "\(model.threats.count) items need your attention"),
            subtitle: model.ruleCount > 0
                ? String(localized: "Checked against \(model.ruleCount) of Apple's XProtect malware signatures.")
                : String(localized: "Apple's XProtect signatures could not be loaded; only startup items were checked.")
        ) {
            OverviewTile(symbol: "ladybug.fill", title: "Malware Scan",
                         subtitle: malware > 0 ? String(localized: "Malware found. Remove it now.") : String(localized: "Threats and suspicious startup items."),
                         value: "\(model.threats.count)", theme: module.theme, badge: malware > 0 ? String(localized: "Threat") : nil) { model.section = .malware }
            OverviewTile(symbol: "lock.shield.fill", title: "Privacy", subtitle: String(localized: "Browsing history, cookies and recent items."),
                         value: formatBytes(privacySize), theme: module.theme) { model.section = .privacy }
            OverviewTile(symbol: "puzzlepiece.extension.fill", title: "Browser Extensions", subtitle: String(localized: "Add-ons that can read the pages you visit."),
                         value: "\(model.extensions.count)", theme: module.theme) { model.section = .extensions }
            OverviewTile(symbol: "lock.open.fill", title: "App Permissions", subtitle: String(localized: "Apps allowed to use your camera, files, screen…"),
                         value: model.permissionsUnreadable ? "—" : "\(appsWithPermissions)", theme: module.theme) { model.section = .permissions }
        } footer: {
            HStack(spacing: 14) {
                PillButton(title: "Scan Again", symbol: "arrow.counterclockwise") { model.scan() }
                PillButton(title: "Saved Wi-Fi Networks", symbol: "wifi") { model.section = .wifi }
            }
        }
    }
}

// MARK: - Malware

private struct MalwareScreen: View {
    @Bindable var model: ProtectionModel
    private let theme = AppModule.protection.theme

    var body: some View {
        DetailScreen(title: "Malware Scan", symbol: "ladybug.fill", theme: theme, onBack: { model.section = nil }) {
            EmptyView()
        } content: {
            if model.threats.isEmpty {
                VStack(spacing: 18) {
                    HeroIllustration(style: .octagon, symbol: "checkmark.shield.fill", theme: theme, size: 220)
                    Text("Your Mac is safe").font(.system(size: 28, weight: .semibold)).foregroundStyle(.white)
                    Text("No malware and no suspicious startup items were found.").foregroundStyle(.white.opacity(0.75))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.threats) { threat in
                            ThreatRow(threat: threat, isSelected: model.selectedThreats.contains(threat.id)) {
                                if model.selectedThreats.contains(threat.id) { model.selectedThreats.remove(threat.id) } else { model.selectedThreats.insert(threat.id) }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassPanel(cornerRadius: 20)
            }
        } bottom: {
            HStack {
                if let report = model.lastReport {
                    ReportBanner(report: report)
                } else {
                    Text("Suspicious items are not always malicious: check where they come from before removing them.")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                ScanButton(title: "Remove", theme: theme, diameter: 84, pulses: false) { model.removeThreats() }
                    .disabled(model.selectedThreats.isEmpty || model.phase == .removing)
                    .opacity(model.selectedThreats.isEmpty ? 0.45 : 1)
            }
        }
    }
}

private struct ThreatRow: View {
    let threat: Threat
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CheckBox(state: isSelected ? .on : .off, action: toggle)
            Image(systemName: threat.isMalware ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 20))
                .foregroundStyle(threat.isMalware ? Color(hex: 0xFF5A5A) : Color(hex: 0xFFD43B))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(threat.displayName).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                Text(description).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                Text(threat.url.path(percentEncoded: false)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([threat.url])
            } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.plain).foregroundStyle(.white.opacity(0.8)).help("Show in Finder")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
    }

    private var description: String {
        switch threat.kind {
        case let .malware(signature): String(localized: "Malware: \(signature)")
        case let .suspiciousPersistence(reason): String(localized: "Suspicious: \(reason)")
        }
    }
}

// MARK: - Privacy

private struct PrivacyScreen: View {
    @Bindable var model: ProtectionModel
    private let theme = AppModule.protection.theme

    var body: some View {
        let owners = Array(Set(model.privacyItems.map(\.owner))).sorted()
        DetailScreen(title: "Privacy", symbol: "lock.shield.fill", theme: theme, onBack: { model.section = nil }) {
            EmptyView()
        } content: {
            Text("Clear the traces your browsing leaves on this Mac. Saved passwords and bookmarks are never touched.")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(owners, id: \.self) { owner in
                        let items = model.privacyItems.filter { $0.owner == owner }
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 10) {
                                AppIconView(bundleID: items.first?.bundleID, fallback: "macwindow")
                                Text(owner).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                                if let running = items.first.flatMap(model.runningBrowser(for:)) {
                                    Text("\(running) is open").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                                        .padding(.horizontal, 7).padding(.vertical, 3)
                                        .background(Capsule().fill(.orange.opacity(0.45)))
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
                            ForEach(items) { item in
                                HStack(spacing: 12) {
                                    CheckBox(state: model.selectedPrivacy.contains(item.id) ? .on : .off) { toggle(item) }
                                    Text(item.title.resolved).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                                    Spacer()
                                    Text(formatBytes(item.size)).font(.system(size: 12, design: .rounded)).foregroundStyle(.white.opacity(0.75))
                                }
                                .padding(.horizontal, 16)
                                .frame(height: 38)
                                .contentShape(Rectangle())
                                .onTapGesture { toggle(item) }
                            }
                        }
                        .padding(.bottom, 8)
                        .glassPanel(cornerRadius: 16)
                    }
                }
            }
            .overlay { if model.privacyItems.isEmpty { EmptyState(symbol: "checkmark.shield.fill", message: "No browsing traces found.") } }
        } bottom: {
            HStack {
                if let message = model.message {
                    Label(message, systemImage: "info.circle.fill").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                } else if let report = model.lastReport {
                    ReportBanner(report: report)
                }
                Spacer()
                ScanButton(title: "Clean", theme: theme, diameter: 84, pulses: false) { model.cleanPrivacy() }
                    .disabled(model.selectedPrivacy.isEmpty || model.phase == .removing)
                    .opacity(model.selectedPrivacy.isEmpty ? 0.45 : 1)
            }
        }
    }

    private func toggle(_ item: PrivacyItem) {
        if model.selectedPrivacy.contains(item.id) { model.selectedPrivacy.remove(item.id) } else { model.selectedPrivacy.insert(item.id) }
    }
}

/// Icon of an installed app from its bundle id, or a symbol.
struct AppIconView: View {
    let bundleID: String?
    var fallback = "app.fill"
    var size: CGFloat = 26

    var body: some View {
        if let id = bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))).resizable().frame(width: size, height: size)
        } else {
            Image(systemName: fallback).font(.system(size: size * 0.7)).foregroundStyle(.white.opacity(0.7)).frame(width: size, height: size)
        }
    }
}

// MARK: - Extensions

private struct ExtensionsScreen: View {
    @Bindable var model: ProtectionModel
    @State private var confirming: BrowserExtension?
    private let theme = AppModule.protection.theme

    var body: some View {
        DetailScreen(title: "Browser Extensions", symbol: "puzzlepiece.extension.fill", theme: theme, onBack: { model.section = nil }) {
            EmptyView()
        } content: {
            Text("Extensions can read and change the pages you visit. Remove the ones you don't recognize. Quit the browser first.")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.extensions) { ext in
                        HStack(spacing: 12) {
                            Image(systemName: "puzzlepiece.extension.fill").font(.system(size: 18)).foregroundStyle(.white.opacity(0.8)).frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ext.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                                Text("\(ext.browser) · \(ext.version)").font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                            }
                            Spacer()
                            Button { confirming = ext } label: { Image(systemName: "trash") }
                                .buttonStyle(.plain).foregroundStyle(.white.opacity(0.8)).help("Remove")
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassPanel(cornerRadius: 20)
            .overlay { if model.extensions.isEmpty { EmptyState(symbol: "puzzlepiece.extension", message: "No browser extensions found.") } }
        } bottom: {
            if let report = model.lastReport { ReportBanner(report: report) }
        }
        .confirmationDialog("Remove \(confirming?.name ?? "")?", isPresented: .init(get: { confirming != nil }, set: { if !$0 { confirming = nil } })) {
            Button("Remove", role: .destructive) { if let ext = confirming { model.remove(ext) } }
        }
    }
}

// MARK: - Wi-Fi

private struct WiFiScreen: View {
    @Bindable var model: ProtectionModel
    private let theme = AppModule.protection.theme

    var body: some View {
        DetailScreen(title: "Saved Wi-Fi Networks", symbol: "wifi", theme: theme, onBack: { model.section = nil }) {
            EmptyView()
        } content: {
            Text("Your Mac joins these networks automatically. Forget the public ones you no longer use: an attacker can imitate them.")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.wifiNetworks, id: \.self) { network in
                        HStack(spacing: 12) {
                            Image(systemName: "wifi").font(.system(size: 16)).foregroundStyle(.white.opacity(0.85)).frame(width: 26)
                            Text(network).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                            Spacer()
                            PillButton(title: "Forget", symbol: "lock.fill") { model.forget(network) }
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassPanel(cornerRadius: 20)
            .overlay { if model.wifiNetworks.isEmpty { EmptyState(symbol: "wifi.slash", message: "No saved networks.") } }
        } bottom: {
            if let message = model.message {
                Text(message).font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
            }
        }
    }
}

// MARK: - Permissions

private struct PermissionsScreen: View {
    @Bindable var model: ProtectionModel
    @Environment(AppModel.self) private var app
    private let theme = AppModule.protection.theme

    var body: some View {
        DetailScreen(title: "App Permissions", symbol: "lock.open.fill", theme: theme, onBack: { model.section = nil }) {
            PillButton(title: "Privacy Settings", symbol: "gearshape.fill") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!)
            }
        } content: {
            if model.permissionsUnreadable {
                VStack(spacing: 14) {
                    Image(systemName: "lock.fill").font(.system(size: 38)).foregroundStyle(.white.opacity(0.7))
                    Text("Revive needs Full Disk Access to read which apps you gave permissions to.")
                        .foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
                    PillButton(title: "Grant Full Disk Access", symbol: "lock.open.fill", prominent: true) { app.showsAccessGuide = true }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassPanel(cornerRadius: 20)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(services, id: \.self) { service in
                            let entries = model.permissions.filter { $0.serviceShortName == service && $0.isAllowed }
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(spacing: 10) {
                                    Image(systemName: PermissionService.symbol(service)).foregroundStyle(.white).frame(width: 22)
                                    Text(PermissionService.title(service)).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                                    Spacer()
                                    Text("\(entries.count)").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.7))
                                }
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                ForEach(entries) { permission in
                                    HStack(spacing: 10) {
                                        AppIconView(bundleID: permission.client, fallback: "terminal.fill", size: 22)
                                        Text(appName(permission.client)).font(.system(size: 13)).foregroundStyle(.white)
                                        Spacer()
                                        PillButton(title: "Reset") { model.reset(permission) }
                                            .help("macOS will ask the app for permission again.")
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(height: 40)
                                }
                            }
                            .padding(.bottom, 6)
                            .glassPanel(cornerRadius: 16)
                        }
                    }
                }
            }
        } bottom: {
            if let message = model.message {
                Text(message).font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    private var services: [String] {
        let present = Set(model.permissions.filter(\.isAllowed).map(\.serviceShortName))
        return present.sorted {
            let a = PermissionService.order.firstIndex(of: $0) ?? 99, b = PermissionService.order.firstIndex(of: $1) ?? 99
            return a != b ? a < b : $0 < $1
        }
    }

    private func appName(_ client: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: client) {
            return FileManager.default.displayName(atPath: url.path(percentEncoded: false)).replacingOccurrences(of: ".app", with: "")
        }
        return (client as NSString).lastPathComponent
    }
}
