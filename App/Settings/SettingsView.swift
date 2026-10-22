import SwiftUI

/// Settings, shown inside the main window with the same look as the modules.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    private let module = AppModule.settings

    var body: some View {
        @Bindable var app = app
        @Bindable var scheduler = app.scheduler
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(module.title).screenTitle()
                Text(module.subtitle).screenSubtitle()
            }
            .padding(.top, 64)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("Safety", symbol: "checkmark.shield.fill") {
                        row("Simulation mode",
                            detail: "Scans and cleanups run normally, but nothing is deleted. Useful to see what Revive would do.") {
                            SettingsSwitch(isOn: $app.dryRun, theme: module.theme)
                        }
                    }

                    section("General", symbol: "slider.horizontal.3") {
                        row("Show the monitor in the menu bar", detail: "CPU, GPU and memory at a glance, with quick actions.") {
                            SettingsSwitch(isOn: $app.showsMenuBar, theme: module.theme)
                        }
                        Divider().overlay(.white.opacity(0.1))
                        row("Open Revive at login", detail: nil) {
                            SettingsSwitch(isOn: .init(get: { scheduler.opensAtLogin }, set: { scheduler.opensAtLogin = $0 }), theme: module.theme)
                        }
                    }

                    section("Updates", symbol: "arrow.down.circle.fill") {
                        row("Revive \(app.updater.currentVersion)", detail: lastCheckText) {
                            PillButton(title: "Check Now", symbol: "arrow.clockwise") { app.updater.checkForUpdates() }
                                .disabled(!app.updater.canCheckForUpdates)
                        }
                        Divider().overlay(.white.opacity(0.1))
                        row("Check for updates automatically", detail: "Revive looks for a new version at launch and every hour.") {
                            SettingsSwitch(isOn: .init(get: { app.updater.automaticallyChecks }, set: { app.updater.automaticallyChecks = $0 }), theme: module.theme)
                        }
                        Divider().overlay(.white.opacity(0.1))
                        row("Download updates in the background", detail: "Updates install when you quit Revive, or when you accept them.") {
                            SettingsSwitch(isOn: .init(get: { app.updater.automaticallyDownloads }, set: { app.updater.automaticallyDownloads = $0 }), theme: module.theme)
                        }
                    }

                    section("Automatic Scan", symbol: "clock.arrow.circlepath") {
                        row("Scan for junk automatically",
                            detail: "Runs while Revive is open and only notifies you. Nothing is removed without you.") {
                            PillPicker(options: [
                                (.never, String(localized: "Never")), (.daily, String(localized: "Every day")), (.weekly, String(localized: "Every week")),
                            ], selection: $scheduler.frequency)
                        }
                        if scheduler.frequency != .never {
                            Divider().overlay(.white.opacity(0.1))
                            row("Notify me above \(scheduler.thresholdGB) GB", detail: nil) {
                                HStack(spacing: 6) {
                                    RoundIconButton(symbol: "minus") { scheduler.thresholdGB = max(1, scheduler.thresholdGB - 1) }
                                    RoundIconButton(symbol: "plus") { scheduler.thresholdGB = min(50, scheduler.thresholdGB + 1) }
                                }
                            }
                        }
                    }

                    section("Permissions", symbol: "lock.fill") {
                        row(app.hasFullDiskAccess ? "Full Disk Access is on" : "Full Disk Access is off",
                            detail: "Needed to clean Mail, Safari, the Trash and other app data.") {
                            if app.hasFullDiskAccess {
                                StatusDot(on: true)
                            } else {
                                PillButton(title: "Grant Access", symbol: "lock.open.fill", prominent: true) { app.showsAccessGuide = true }
                            }
                        }
                        Divider().overlay(.white.opacity(0.1))
                        row(helperTitle,
                            detail: "Runs a fixed list of maintenance tasks with administrator rights, so they don't ask for your password each time.") {
                            switch app.privileged.helperState {
                            case .enabled:
                                PillButton(title: "Uninstall", symbol: "trash") { Task { await app.privileged.uninstallHelper() } }
                            case .needsApproval:
                                PillButton(title: "Open Login Items", symbol: "gearshape.fill") { app.privileged.installHelper() }
                            case .notInstalled:
                                PillButton(title: "Install", symbol: "key.fill") { app.privileged.installHelper() }
                            case .unavailable:
                                EmptyView()
                            }
                        }
                        if let error = app.privileged.lastError {
                            Text(error).font(.system(size: 11)).foregroundStyle(Color(hex: 0xFFD43B))
                        }
                    }

                    section("Never Touch", symbol: "hand.raised.fill") {
                        Text("Revive never scans or removes anything inside these folders.")
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                        ForEach(app.exclusions, id: \.self) { path in
                            HStack(spacing: 10) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 20, height: 20)
                                Text(path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                    .font(.system(size: 13)).foregroundStyle(.white)
                                    .lineLimit(1).truncationMode(.middle)
                                Spacer()
                                RoundIconButton(symbol: "xmark") {
                                    withAnimation { app.exclusions.removeAll { $0 == path } }
                                }
                            }
                        }
                        PillButton(title: "Add Folder…", symbol: "folder.badge.plus") { addExclusion() }
                    }
                }
                .padding(.bottom, 30)
            }
            .scrollIndicators(.never)
        }
        .padding(.horizontal, 44)
        .onAppear { app.privileged.refresh() }
    }

    private var lastCheckText: LocalizedStringResource {
        if let date = app.updater.lastCheck {
            return "Last checked \(date.formatted(.relative(presentation: .named)))."
        }
        return "Not checked yet."
    }

    private var helperTitle: LocalizedStringResource {
        switch app.privileged.helperState {
        case .enabled: "Administrator helper installed"
        case .needsApproval: "Waiting for your approval in System Settings"
        case .notInstalled: "Administrator helper not installed"
        case .unavailable: "Administrator helper unavailable in this build"
        }
    }

    private func section<Content: View>(_ title: LocalizedStringResource, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                FeatureBadge(symbol: symbol, theme: module.theme, size: 28)
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            }
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 20)
    }

    private func row<Control: View>(_ title: LocalizedStringResource, detail: LocalizedStringResource?, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                if let detail {
                    Text(detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control()
        }
    }

    private func addExclusion() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            let paths = panel.urls.map { $0.path(percentEncoded: false) }
            withAnimation { app.exclusions.append(contentsOf: paths.filter { !app.exclusions.contains($0) }) }
        }
    }
}

/// Switch in the app's colors.
struct SettingsSwitch: View {
    @Binding var isOn: Bool
    let theme: ModuleTheme

    var body: some View {
        Toggle("", isOn: $isOn)
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(theme.button)
    }
}

struct RoundIconButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.white.opacity(0.15)))
        }
        .buttonStyle(PressableStyle())
    }
}

struct StatusDot: View {
    let on: Bool

    var body: some View {
        Image(systemName: on ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.system(size: 20))
            .foregroundStyle(on ? .white : Color(hex: 0xFFD43B))
    }
}
