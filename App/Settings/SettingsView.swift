import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        @Bindable var scheduler = app.scheduler
        Form {
            Section {
                Toggle(isOn: $app.dryRun) {
                    Text("Simulation mode")
                    Text("Scans and cleanups run normally, but nothing is deleted. Useful to see what Lucent would do.")
                }
            }

            Section("General") {
                Toggle("Show the monitor in the menu bar", isOn: $app.showsMenuBar)
                Toggle("Open Lucent at login", isOn: .init(get: { app.scheduler.opensAtLogin }, set: { app.scheduler.opensAtLogin = $0 }))
            }

            Section {
                Picker("Scan for junk automatically", selection: $scheduler.frequency) {
                    Text("Never").tag(AutoScanScheduler.Frequency.never)
                    Text("Every day").tag(AutoScanScheduler.Frequency.daily)
                    Text("Every week").tag(AutoScanScheduler.Frequency.weekly)
                }
                if scheduler.frequency != .never {
                    Stepper("Notify me above \(scheduler.thresholdGB) GB", value: $scheduler.thresholdGB, in: 1...50)
                }
            } header: {
                Text("Automatic Scan")
            } footer: {
                Text("Runs while Lucent is open and only notifies you. Nothing is removed without you.")
            }

            Section {
                LabeledContent {
                    switch app.privileged.helperState {
                    case .enabled:
                        Button("Uninstall") { Task { await app.privileged.uninstallHelper() } }
                    case .needsApproval:
                        Button("Open Login Items") { app.privileged.installHelper() }
                    default:
                        Button("Install") { app.privileged.installHelper() }
                    }
                } label: {
                    Label(helperStatus, systemImage: app.privileged.helperState == .enabled ? "checkmark.circle.fill" : "key.fill")
                }
                if let error = app.privileged.lastError {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Administrator Helper")
            } footer: {
                Text("Runs a fixed list of maintenance tasks with administrator rights, so they don't ask for your password each time.")
            }

            Section("Full Disk Access") {
                LabeledContent {
                    Button("Open System Settings") { app.openFullDiskAccessSettings() }
                } label: {
                    Label(app.hasFullDiskAccess ? "Granted" : "Not granted",
                          systemImage: app.hasFullDiskAccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                }
            }

            Section {
                if app.exclusions.isEmpty {
                    Text("No excluded folders").foregroundStyle(.secondary)
                }
                ForEach(app.exclusions, id: \.self) { path in
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 18, height: 18)
                        Text(path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button(role: .destructive) {
                            app.exclusions.removeAll { $0 == path }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button("Add Folder…") { addExclusion() }
            } header: {
                Text("Never touch")
            } footer: {
                Text("Lucent never scans or removes anything inside these folders.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 640)
        .onAppear { app.privileged.refresh() }
    }

    private var helperStatus: LocalizedStringResource {
        switch app.privileged.helperState {
        case .enabled: "Installed"
        case .needsApproval: "Waiting for your approval in System Settings"
        case .notInstalled: "Not installed"
        case .unavailable: "Unavailable in this build"
        }
    }

    private func addExclusion() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            let paths = panel.urls.map { $0.path(percentEncoded: false) }
            app.exclusions.append(contentsOf: paths.filter { !app.exclusions.contains($0) })
        }
    }
}
