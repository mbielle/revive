import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        Form {
            Section {
                Toggle(isOn: $app.dryRun) {
                    Text("Simulation mode")
                    Text("Scans and cleanups run normally, but nothing is deleted. Useful to see what Lucent would do.")
                }
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
        .frame(width: 520, height: 460)
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
