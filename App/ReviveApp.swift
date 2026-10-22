import SwiftUI

@main
struct ReviveApp: App {
    @State private var app = AppModel()
    @AppStorage("didShowAccessGuide") private var didShowAccessGuide = false

    var body: some Scene {
        Window("Revive", id: "main") {
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
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { app.updater.checkForUpdates() }
                    .disabled(!app.updater.canCheckForUpdates)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { app.selection = .settings }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandMenu("Go") {
                ForEach(Array((AppModule.mainModules + AppModule.footerModules).enumerated()), id: \.element) { index, module in
                    Button(String(localized: module.title)) { app.selection = module }
                        .keyboardShortcut(index < 9 ? KeyEquivalent(Character("\(index + 1)")) : "0", modifiers: .command)
                }
            }
        }


        #if DEBUG
        // `-previewMenuBar YES` shows the menu bar panel in a window, for screenshots.
        Window("Menu Bar Preview", id: "menubar-preview") {
            MenuBarPanel().environment(app)
        }
        .windowResizability(.contentSize)
        #endif

        MenuBarExtra("Revive", systemImage: "infinity", isInserted: $app.showsMenuBar) {
            MenuBarPanel()
                .environment(app)
        }
        .menuBarExtraStyle(.window)
    }
}
