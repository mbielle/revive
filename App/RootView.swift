import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        let module = app.selection

        HStack(spacing: 0) {
            Sidebar()
                .frame(width: 268)
            Rectangle().fill(.white.opacity(0.06)).frame(width: 1)
            ZStack(alignment: .topTrailing) {
                content(for: module)
                    .id(module)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                TopBar()
                    .padding(.top, 14)
                    .padding(.trailing, 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background { ModuleBackground(theme: module.theme).animation(.easeInOut(duration: 0.45), value: module) }
        .animation(.easeInOut(duration: 0.3), value: module)
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $app.showsAccessGuide) {
            FullDiskAccessGuide()
                .environment(app)
        }
    }

    @ViewBuilder
    private func content(for module: AppModule) -> some View {
        switch module {
        case .smartCare: SmartCareView(model: app.smartCare)
        case .cleanup: CleanupView(model: app.cleanup)
        case .spaceLens: SpaceLensView(model: app.spaceLens)
        case .applications: ApplicationsView(model: app.applications)
        case .performance: PerformanceView(model: app.performance)
        case .protection: ProtectionView(model: app.protection)
        case .myClutter: ClutterView(model: app.clutter)
        case .cloudCleanup: CloudView(model: app.cloud)
        case .myTools: ToolsView(model: app.tools)
        case .myActivity: ActivityView(model: app.activity)
        }
    }
}

/// Top-right corner: access warning, simulation badge and settings.
struct TopBar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 10) {
            if app.dryRun {
                Label("Simulation mode", systemImage: "testtube.2")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(.black.opacity(0.25)))
                    .help("Nothing is deleted while simulation mode is on. Change it in Settings.")
            }
            if !app.hasFullDiskAccess {
                PillButton(title: "Grant Full Disk Access", symbol: "lock.open.fill", prominent: true) {
                    app.showsAccessGuide = true
                }
            }
            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(.white.opacity(0.14)))
            }
            .buttonStyle(PressableStyle())
            .help("Settings")
        }
    }
}
