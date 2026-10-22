import ReviveKit
import SwiftUI

struct PerformanceView: View {
    @Bindable var model: PerformanceModel
    private let module = AppModule.performance

    var body: some View {
        Group {
            switch model.phase {
            case .idle:
                ModuleLanding(module: module) {
                    ScanButton(title: "Scan", theme: module.theme) { model.scan() }
                }
            case .scanning:
                WorkingView(module: module, title: "Checking performance…", progress: nil, detail: "launchd", stat: nil, onStop: nil)
            case .ready:
                switch model.section {
                case nil: overview
                case .maintenance: MaintenanceScreen(model: model)
                case .loginItems: LoginItemsScreen(model: model)
                case .backgroundItems: BackgroundItemsScreen(model: model)
                case .consumers: ConsumersScreen(model: model)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.phase)
        .animation(.easeInOut(duration: 0.3), value: model.section)
    }

    private var overview: some View {
        let recommended = MaintenanceTask.allCases.filter(\.isRecommended).count
        return OverviewScreen(
            title: String(localized: "Your Mac's performance"),
            subtitle: String(localized: "Memory in use: \(Int((model.memory?.usedFraction ?? 0) * 100))%. Pick what to tune up.")
        ) {
            OverviewTile(symbol: "wrench.and.screwdriver.fill", title: "Maintenance Tasks",
                         subtitle: String(localized: "Scripts that fix common slowdowns, \(recommended) recommended."),
                         value: "\(MaintenanceTask.allCases.count)", theme: module.theme) { model.section = .maintenance }
            OverviewTile(symbol: "power", title: "Login Items", subtitle: String(localized: "Apps that open when you log in."),
                         value: model.loginItems.map { "\($0.count)" } ?? "—", theme: module.theme) { model.section = .loginItems }
            OverviewTile(symbol: "gearshape.2.fill", title: "Background Items",
                         subtitle: String(localized: "Agents and daemons apps installed."),
                         value: "\(model.launchItems.count)", theme: module.theme) { model.section = .backgroundItems }
            OverviewTile(symbol: "gauge.with.dots.needle.67percent", title: "Heavy Consumers",
                         subtitle: String(localized: "Apps using the most CPU and memory right now."),
                         value: "\(model.heavyConsumers.count)", theme: module.theme) { model.section = .consumers }
        } footer: {
            PillButton(title: "Scan Again", symbol: "arrow.counterclockwise") { model.scan() }
        }
    }
}

// MARK: - Maintenance

private struct MaintenanceScreen: View {
    @Bindable var model: PerformanceModel
    @Environment(AppModel.self) private var app
    private let theme = AppModule.performance.theme

    var body: some View {
        DetailScreen(title: "Maintenance Tasks", symbol: "wrench.and.screwdriver.fill", theme: theme, onBack: { model.section = nil }) {
            EmptyView()
        } content: {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(MaintenanceTask.allCases) { task in
                        TaskRow(task: task, isSelected: model.selectedTasks.contains(task), state: model.taskStates[task] ?? .pending) {
                            model.toggle(task)
                        }
                    }
                }
            }
            HelperBanner()
        } bottom: {
            HStack {
                Spacer()
                ScanButton(title: "Run", theme: theme, diameter: 84, pulses: false) { Task { await model.runTasks() } }
                    .disabled(model.selectedTasks.isEmpty || model.isRunningTasks)
                    .opacity(model.selectedTasks.isEmpty ? 0.45 : 1)
            }
        }
    }
}

private struct TaskRow: View {
    let task: MaintenanceTask
    let isSelected: Bool
    let state: PerformanceModel.TaskState
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            CheckBox(state: isSelected ? .on : .off, action: toggle)
            FeatureBadge(symbol: task.symbol, theme: AppModule.performance.theme, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(task.title.resolved).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    if task.privilegedCommand != nil {
                        Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                            .help("Needs administrator rights")
                    }
                }
                Text(task.detail.resolved).font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            switch state {
            case .pending: EmptyView()
            case .running: ProgressView().controlSize(.small).tint(.white)
            case .done: Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(.white)
            case let .failed(reason):
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 18)).foregroundStyle(Color(hex: 0xFFD43B)).help(reason)
            }
        }
        .padding(14)
        .glassPanel(cornerRadius: 16)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
    }
}

/// Offers to install the helper so administrator tasks stop asking for a password.
struct HelperBanner: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let runner = app.privileged
        if runner.helperState != .enabled {
            HStack(spacing: 12) {
                Image(systemName: "key.fill").foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(runner.helperState == .needsApproval ? "Allow Revive's helper in System Settings" : "Tasks with a lock ask for your password")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    Text("Install the helper once to run them without a password prompt.")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
                PillButton(title: runner.helperState == .needsApproval ? "Open Settings" : "Install Helper", symbol: "lock.open.fill") {
                    runner.installHelper()
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.2)))
        }
    }
}

// MARK: - Login items

private struct LoginItemsScreen: View {
    @Bindable var model: PerformanceModel
    private let theme = AppModule.performance.theme

    var body: some View {
        DetailScreen(title: "Login Items", symbol: "power", theme: theme, onBack: { model.section = nil }) {
            PillButton(title: "Open Login Items Settings", symbol: "gearshape.fill") { model.openLoginItemsSettings() }
        } content: {
            Group {
                if let items = model.loginItems {
                    if items.isEmpty {
                        EmptyState(symbol: "power", message: "No app opens at login.")
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(items) { item in LoginItemRow(item: item) }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "lock.shield.fill").font(.system(size: 38)).foregroundStyle(.white.opacity(0.7))
                        Text("macOS keeps the list of login items in a protected database.")
                            .foregroundStyle(.white.opacity(0.8))
                        if let error = model.loginItemsError {
                            Text(error).font(.system(size: 12)).foregroundStyle(Color(hex: 0xFFD43B))
                        }
                        if model.loadingLoginItems {
                            ProgressView().tint(.white)
                        } else {
                            PillButton(title: "Show Login Items", symbol: "lock.open.fill", prominent: true) { model.loadLoginItems() }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassPanel(cornerRadius: 20)
        } bottom: {
            Text("To turn a login item off, use the switch next to it in System Settings › General › Login Items.")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
        }
    }
}

private struct LoginItemRow: View {
    let item: BackgroundTaskItem

    var body: some View {
        HStack(spacing: 12) {
            if let path = item.url.flatMap(URL.init(string:))?.path(percentEncoded: false) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 30, height: 30)
            } else {
                Image(systemName: "app.fill").font(.system(size: 24)).foregroundStyle(.white.opacity(0.6)).frame(width: 30)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                Text(item.developer ?? item.bundleID ?? item.type).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            Text(item.isEnabled ? "On" : "Off")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(item.isEnabled ? .black.opacity(0.8) : .white.opacity(0.8))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(item.isEnabled ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.15))))
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }
}

// MARK: - Background items

private struct BackgroundItemsScreen: View {
    @Bindable var model: PerformanceModel
    @State private var confirming: LaunchItem?
    private let theme = AppModule.performance.theme

    var body: some View {
        DetailScreen(title: "Background Items", symbol: "gearshape.2.fill", theme: theme, onBack: { model.section = nil }) {
            EmptyView()
        } content: {
            Text("Helpers that apps installed to run in the background. Removing one stops it for good; the app may ask to reinstall it.")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.launchItems) { item in
                        LaunchItemRow(item: item, isBusy: model.busyItems.contains(item.id),
                                      onToggle: { model.setLoaded(item, $0) }, onRemove: { confirming = item })
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassPanel(cornerRadius: 20)
            .overlay { if model.launchItems.isEmpty { EmptyState(symbol: "checkmark.circle.fill", message: "No background items.") } }
        } bottom: {
            EmptyView()
        }
        .confirmationDialog("Remove \(confirming?.label ?? "")?", isPresented: .init(get: { confirming != nil }, set: { if !$0 { confirming = nil } })) {
            Button("Remove", role: .destructive) { if let item = confirming { model.remove(item) } }
        } message: {
            Text("It is stopped and its file goes to the Trash.")
        }
    }
}

private struct LaunchItemRow: View {
    let item: LaunchItem
    let isBusy: Bool
    let onToggle: (Bool) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.scope == .daemon ? "gearshape.2.fill" : "person.crop.circle.badge.clock")
                .font(.system(size: 18)).foregroundStyle(.white.opacity(0.85)).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(scopeLabel)
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(.white.opacity(0.14)))
                }
                Text(item.signer ?? item.program ?? "")
                    .font(.system(size: 11)).foregroundStyle(item.signer == nil ? Color(hex: 0xFFD43B) : .white.opacity(0.55))
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if isBusy {
                ProgressView().controlSize(.small).tint(.white)
            } else {
                if item.scope == .userAgent, let loaded = item.isLoaded {
                    Toggle("", isOn: .init(get: { loaded }, set: { onToggle($0) }))
                        .toggleStyle(.switch).labelsHidden().controlSize(.small).tint(AppModule.performance.theme.button)
                        .help(loaded ? "Running" : "Stopped")
                }
                Button(action: onRemove) {
                    Image(systemName: "trash").foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help(item.requiresAdministrator ? "Remove (needs administrator rights)" : "Remove")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.plist]) }
        }
    }

    private var scopeLabel: String {
        switch item.scope {
        case .userAgent: String(localized: "You")
        case .globalAgent: String(localized: "All users")
        case .daemon: String(localized: "System")
        }
    }
}

// MARK: - Heavy consumers

private struct ConsumersScreen: View {
    @Bindable var model: PerformanceModel
    private let theme = AppModule.performance.theme

    var body: some View {
        DetailScreen(title: "Heavy Consumers", symbol: "gauge.with.dots.needle.67percent", theme: theme, onBack: { model.section = nil }) {
            EmptyView()
        } content: {
            HStack(spacing: 16) {
                Gauge(label: "CPU", fraction: model.cpu, theme: theme)
                Gauge(label: "Memory", fraction: model.memory?.usedFraction ?? 0, theme: theme,
                      detail: model.memory.map { "\(formatBytes(Int64($0.used))) / \(formatBytes(Int64($0.total)))" })
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.heavyConsumers) { process in
                        let (name, icon) = model.appName(for: process)
                        HStack(spacing: 12) {
                            if let icon {
                                Image(nsImage: icon).resizable().frame(width: 28, height: 28)
                            } else {
                                Image(systemName: "terminal.fill").font(.system(size: 18)).foregroundStyle(.white.opacity(0.6)).frame(width: 28)
                            }
                            Text(name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                            Spacer()
                            Text(String(format: "%.1f%%", process.cpu)).font(.system(size: 12, design: .rounded)).foregroundStyle(.white.opacity(0.8))
                                .frame(width: 60, alignment: .trailing)
                            Text(formatBytes(Int64(process.memory))).font(.system(size: 12, design: .rounded)).foregroundStyle(.white.opacity(0.8))
                                .frame(width: 80, alignment: .trailing)
                            if icon != nil {
                                PillButton(title: "Quit") { model.quit(process) }
                            } else {
                                Color.clear.frame(width: 58, height: 1)
                            }
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 48)
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassPanel(cornerRadius: 20)
        } bottom: {
            EmptyView()
        }
        .onAppear { model.startMonitoring() }
        .onDisappear { model.stopMonitoring() }
    }
}

struct Gauge: View {
    let label: LocalizedStringResource
    let fraction: Double
    let theme: ModuleTheme
    var detail: String?

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                ProgressRing(fraction: fraction, theme: theme, lineWidth: 6)
                Text("\(Int(fraction * 100))%").font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            }
            .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)) }
            }
            Spacer()
        }
        .padding(14)
        .glassPanel(cornerRadius: 16)
    }
}
