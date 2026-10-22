import SwiftUI

@main
struct LucentApp: App {
    @State private var app = AppModel()
    @AppStorage("didShowAccessGuide") private var didShowAccessGuide = false

    var body: some Scene {
        Window("Lucent", id: "main") {
            RootView()
                .environment(app)
                .frame(minWidth: 1040, minHeight: 680)
                .onAppear {
                    if !app.hasFullDiskAccess && !didShowAccessGuide {
                        app.showsAccessGuide = true
                        didShowAccessGuide = true
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    app.refreshAccess()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1160, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Go") {
                ForEach(Array((AppModule.mainModules + AppModule.footerModules).enumerated()), id: \.element) { index, module in
                    Button(String(localized: module.title)) { app.selection = module }
                        .keyboardShortcut(index < 9 ? KeyEquivalent(Character("\(index + 1)")) : "0", modifiers: .command)
                }
            }
        }

        Settings {
            SettingsView()
                .environment(app)
        }

        MenuBarExtra("Lucent", systemImage: "sparkles", isInserted: $app.showsMenuBar) {
            MenuBarPanel()
                .environment(app)
        }
        .menuBarExtraStyle(.window)
    }
}
