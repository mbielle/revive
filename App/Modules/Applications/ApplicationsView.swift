import LucentKit
import SwiftUI

struct ApplicationsView: View {
    @Bindable var model: ApplicationsModel
    private let module = AppModule.applications

    var body: some View {
        Group {
            switch model.phase {
            case .idle:
                ModuleLanding(module: module) {
                    ScanButton(title: "Scan", theme: module.theme) { model.scan() }
                }
            case .scanning:
                WorkingView(module: module, title: "Looking at your apps…", progress: nil, detail: "/Applications", stat: nil, onStop: nil)
            case .ready, .removing:
                switch model.section {
                case nil: overview
                case .uninstaller: UninstallerScreen(model: model)
                case .updater: UpdaterScreen(model: model)
                case .leftovers:
                    FileListScreen(model: model, title: "Leftovers", symbol: "puzzlepiece.extension.fill", items: model.orphans,
                                   explanation: "Support files of apps that are no longer installed. Check each one: some tools keep data without an app.",
                                   policy: .appRemoval)
                case .installers:
                    FileListScreen(model: model, title: "Installation Files", symbol: "shippingbox.fill", items: model.installers,
                                   explanation: "Disk images and installer packages in Downloads and on the Desktop. Once an app is installed, you rarely need them.",
                                   policy: .userInitiated)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.phase)
        .animation(.easeInOut(duration: 0.3), value: model.section)
        .sheet(isPresented: $model.showsUninstallReview) { UninstallReview(model: model) }
    }

    private var overview: some View {
        let orphanSize = model.orphans.reduce(0) { $0 + $1.size }
        let installerSize = model.installers.reduce(0) { $0 + $1.size }
        return OverviewScreen(
            title: String(localized: "\(model.apps.count) apps installed"),
            subtitle: String(localized: "They take \(formatBytes(model.totalAppsSize)). \(model.unusedApps.count) haven't been opened in 3 months.")
        ) {
            OverviewTile(symbol: "xmark.app.fill", title: "Uninstaller", subtitle: String(localized: "Remove apps and every file they left behind."),
                         value: formatBytes(model.totalAppsSize), theme: module.theme) { model.section = .uninstaller }
            OverviewTile(symbol: "arrow.down.app.fill", title: "Updater",
                         subtitle: model.checkingUpdates ? String(localized: "Checking for new versions…") : String(localized: "Keep your apps up to date."),
                         value: model.checkingUpdates ? "…" : "\(model.updates.count)", theme: module.theme,
                         badge: model.updates.isEmpty ? nil : String(localized: "New")) { model.section = .updater }
            OverviewTile(symbol: "puzzlepiece.extension.fill", title: "Leftovers", subtitle: String(localized: "Files of apps you already deleted."),
                         value: formatBytes(orphanSize), theme: module.theme) { model.section = .leftovers }
            OverviewTile(symbol: "shippingbox.fill", title: "Installation Files", subtitle: String(localized: "Installers you no longer need."),
                         value: formatBytes(installerSize), theme: module.theme) { model.section = .installers }
        } footer: {
            HStack(spacing: 14) {
                PillButton(title: "Scan Again", symbol: "arrow.counterclockwise") { model.scan() }
                if let report = model.lastReport, report.removedCount > 0 {
                    Text(report.wasSimulated ? "Simulated: \(formatBytes(report.freedBytes))" : "Moved \(formatBytes(report.freedBytes)) to the Trash")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                }
            }
        }
    }
}

// MARK: - Uninstaller

private struct UninstallerScreen: View {
    @Bindable var model: ApplicationsModel
    private let theme = AppModule.applications.theme

    var body: some View {
        DetailScreen(title: "Uninstaller", symbol: "xmark.app.fill", theme: theme, onBack: { model.section = nil }) {
            SearchField(text: $model.search)
        } content: {
            HStack {
                PillPicker(options: [
                    (.all, String(localized: "All")), (.unused, String(localized: "Unused")), (.large, String(localized: "Large")),
                    (.appStore, String(localized: "App Store")), (.homebrew, String(localized: "Homebrew")),
                ], selection: $model.filter)
                Spacer()
                PillPicker(options: [
                    (.size, String(localized: "Size")), (.name, String(localized: "Name")), (.lastUsed, String(localized: "Last Opened")),
                ], selection: $model.sort)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.visibleApps) { app in
                        AppRow(app: app, isSelected: model.selectedApps.contains(app.id)) { model.toggleApp(app) }
                    }
                }
                .padding(.vertical, 6)
            }
            .glassPanel(cornerRadius: 20)
            .overlay {
                if model.visibleApps.isEmpty { EmptyState(symbol: "app.dashed", message: "No apps match.") }
            }
        } bottom: {
            HStack(spacing: 16) {
                Spacer()
                if !model.selectedApps.isEmpty {
                    Text("\(model.selectedApps.count) selected · \(formatBytes(model.selectedAppsSize))")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                }
                ScanButton(title: "Uninstall", theme: theme, diameter: 84, pulses: false) { model.prepareUninstall() }
                    .disabled(model.selectedApps.isEmpty || model.phase == .removing)
                    .opacity(model.selectedApps.isEmpty ? 0.45 : 1)
            }
        }
    }
}

private struct AppRow: View {
    let app: InstalledApp
    let isSelected: Bool
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            CheckBox(state: isSelected ? .on : .off, action: toggle)
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path(percentEncoded: false)))
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(app.version).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    SourceBadge(source: app.source)
                }
                Text(lastUsedText)
                    .font(.system(size: 11))
                    .foregroundStyle(app.isUnused() ? Color(hex: 0xFFD43B) : .white.opacity(0.55))
            }
            Spacer()
            Text(formatBytes(app.size))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(.white.opacity(hovering ? 0.06 : 0))
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
        }
    }

    private var lastUsedText: String {
        guard let date = app.lastUsed else { return String(localized: "Last opened: unknown") }
        return String(localized: "Last opened \(date.formatted(.relative(presentation: .named)))")
    }
}

private struct SourceBadge: View {
    let source: InstalledApp.Source

    var body: some View {
        if let label {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(.white.opacity(0.14)))
        }
    }

    private var label: String? {
        switch source {
        case .appStore: "App Store"
        case .homebrew: "Homebrew"
        case .sparkle: nil
        case .other: nil
        }
    }
}

/// Review of everything that will be removed, app by app.
private struct UninstallReview: View {
    @Bindable var model: ApplicationsModel
    @Environment(\.dismiss) private var dismiss
    private let theme = AppModule.applications.theme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review before uninstalling").font(.system(size: 22, weight: .semibold))
            Text("Everything goes to the Trash. Uncheck an app itself to only reset it: its settings and data are removed, the app stays.")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(model.uninstallPlan, id: \.app.id) { entry in
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 10) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: entry.app.url.path(percentEncoded: false)))
                                    .resizable().frame(width: 26, height: 26)
                                Text(entry.app.name).font(.system(size: 15, weight: .semibold))
                                Spacer()
                                Text(formatBytes(entry.files.reduce(0) { $0 + $1.size }))
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            ForEach(entry.files) { file in
                                FileItemRow(item: file, isSelected: model.planSelection.contains(file.id)) {
                                    if model.planSelection.contains(file.id) { model.planSelection.remove(file.id) } else { model.planSelection.insert(file.id) }
                                }
                            }
                        }
                        .glassPanel(cornerRadius: 16)
                    }
                }
            }
            HStack {
                PillButton(title: "Cancel") { dismiss() }
                Spacer()
                Text(formatBytes(model.planSize)).font(.system(size: 15, weight: .semibold, design: .rounded))
                PillButton(title: "Uninstall", symbol: "trash.fill", prominent: true) { model.confirmUninstall() }
                    .disabled(model.planSelection.isEmpty)
            }
        }
        .foregroundStyle(.white)
        .padding(26)
        .frame(width: 640, height: 560)
        .background { ModuleBackground(theme: theme) }
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Updater

private struct UpdaterScreen: View {
    @Bindable var model: ApplicationsModel
    private let theme = AppModule.applications.theme

    var body: some View {
        DetailScreen(title: "Updater", symbol: "arrow.down.app.fill", theme: theme, onBack: { model.section = nil }) {
            PillButton(title: "Check Again", symbol: "arrow.clockwise") { model.checkUpdates() }
                .disabled(model.checkingUpdates)
        } content: {
            Group {
                if model.checkingUpdates && model.updates.isEmpty {
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large).tint(.white)
                        Text("Checking for new versions…").foregroundStyle(.white.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.updates.isEmpty {
                    EmptyState(symbol: "checkmark.seal.fill", message: "All your apps are up to date.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(model.updates) { update in
                                UpdateRow(update: update, isUpgrading: model.upgrading.contains(update.id)) { model.update(update) }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassPanel(cornerRadius: 20)
        } bottom: {
            Text("Lucent checks each app's own update feed, the Mac App Store and Homebrew. Nothing else is sent.")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
        }
    }
}

private struct UpdateRow: View {
    let update: AppUpdate
    let isUpgrading: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: update.app.url.path(percentEncoded: false)))
                .resizable().frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(update.app.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    SourceBadge(source: update.app.source)
                }
                Text("\(update.app.version) → \(update.newVersion)")
                    .font(.system(size: 12, design: .rounded)).foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            if isUpgrading {
                ProgressView().controlSize(.small).tint(.white)
            } else {
                PillButton(title: actionTitle, symbol: "arrow.down.circle.fill", action: action)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    private var actionTitle: LocalizedStringResource {
        switch update.app.source {
        case .appStore: "App Store"
        case .homebrew: "Update"
        default: "Open to Update"
        }
    }
}

// MARK: - Leftovers / installers

private struct FileListScreen: View {
    @Bindable var model: ApplicationsModel
    let title: LocalizedStringResource
    let symbol: String
    let items: [CleanupItem]
    let explanation: LocalizedStringResource
    let policy: SafetyGuard.Policy
    private let theme = AppModule.applications.theme

    var body: some View {
        let selected = items.filter { model.selectedFiles.contains($0.id) }
        DetailScreen(title: title, symbol: symbol, theme: theme, onBack: { model.section = nil }) {
            EmptyView()
        } content: {
            Text(explanation).font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        FileItemRow(item: item, isSelected: model.selectedFiles.contains(item.id)) {
                            if model.selectedFiles.contains(item.id) { model.selectedFiles.remove(item.id) } else { model.selectedFiles.insert(item.id) }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassPanel(cornerRadius: 20)
            .overlay { if items.isEmpty { EmptyState(symbol: "checkmark.circle.fill", message: "Nothing to remove here.") } }
        } bottom: {
            HStack(spacing: 16) {
                if !items.isEmpty {
                    PillButton(title: selected.count == items.count ? "Deselect All" : "Select All", symbol: "checklist") {
                        if selected.count == items.count { model.selectedFiles.subtract(items.map(\.id)) } else { model.selectedFiles.formUnion(items.map(\.id)) }
                    }
                }
                Spacer()
                if !selected.isEmpty {
                    Text("\(selected.count) selected · \(formatBytes(selected.reduce(0) { $0 + $1.size }))")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                }
                ScanButton(title: "Remove", theme: theme, diameter: 84, pulses: false) { model.removeFiles(items, policy: policy) }
                    .disabled(selected.isEmpty || model.phase == .removing)
                    .opacity(selected.isEmpty ? 0.45 : 1)
            }
        }
    }
}
