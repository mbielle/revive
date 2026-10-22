import AppKit
import LucentKit
import SwiftUI

@MainActor @Observable
final class PerformanceModel {
    enum Phase: Equatable { case idle, scanning, ready }
    enum Section: Hashable { case maintenance, loginItems, backgroundItems, consumers }
    enum TaskState: Equatable { case pending, running, done, failed(String) }

    private(set) var phase: Phase = .idle
    var section: Section?

    // Maintenance
    var selectedTasks: Set<MaintenanceTask> = Set(MaintenanceTask.allCases.filter(\.isRecommended))
    private(set) var taskStates: [MaintenanceTask: TaskState] = [:]
    private(set) var isRunningTasks = false

    // Launch items and login items
    private(set) var launchItems: [LaunchItem] = []
    private(set) var loginItems: [BackgroundTaskItem]?
    private(set) var loadingLoginItems = false
    private(set) var loginItemsError: String?
    private(set) var busyItems: Set<String> = []

    // Live usage
    private(set) var processes: [ProcessUsage] = []
    private(set) var memory: MemoryUsage?
    private(set) var cpu: Double = 0
    @ObservationIgnored private var lastTicks: SystemMetrics.CPUTicks?
    @ObservationIgnored private var monitor: Task<Void, Never>?

    @ObservationIgnored unowned let app: AppModel

    init(app: AppModel) {
        self.app = app
    }

    /// Opens a section, scanning first if needed (used by My Tools).
    func open(_ section: Section) {
        self.section = section
        if phase == .idle { scan() }
    }

    func scan() {
        phase = .scanning
        Task {
            let home = app.safetyGuard.home
            launchItems = await Task.detached { LaunchItemScanner(home: home).scan() }.value
            await sample()
            try? await Task.sleep(for: .milliseconds(600))
            await sample()
            phase = .ready
        }
    }

    // MARK: Maintenance

    func toggle(_ task: MaintenanceTask) {
        if selectedTasks.contains(task) { selectedTasks.remove(task) } else { selectedTasks.insert(task) }
    }

    /// Runs the checked tasks. Administrator tasks share a single authorization.
    func runTasks(_ tasks: [MaintenanceTask]? = nil) async {
        let tasks = (tasks ?? MaintenanceTask.allCases.filter { selectedTasks.contains($0) })
        guard !tasks.isEmpty, !isRunningTasks else { return }
        isRunningTasks = true
        for task in tasks { taskStates[task] = .running }

        if app.dryRun {
            try? await Task.sleep(for: .seconds(1))
            for task in tasks { taskStates[task] = .done }
            isRunningTasks = false
            return
        }

        let admin = tasks.filter { $0.privilegedCommand != nil }
        if !admin.isEmpty {
            let result = await app.privileged.run(admin.compactMap(\.privilegedCommand))
            for task in admin {
                taskStates[task] = result.succeeded ? .done : .failed(Self.describe(result))
            }
        }
        for task in tasks where task.privilegedCommand == nil {
            let result = await Task.detached { task.runAsUser() }.value
            taskStates[task] = result.succeeded ? .done : .failed(Self.describe(result))
        }
        isRunningTasks = false
    }

    private static func describe(_ result: PrivilegedResult) -> String {
        if result.output.contains("-128") || result.output.lowercased().contains("canceled") {
            return String(localized: "Canceled")
        }
        return result.output.split(separator: "\n").last.map(String.init) ?? String(localized: "Failed")
    }

    // MARK: Background items

    func setLoaded(_ item: LaunchItem, _ loaded: Bool) {
        guard item.scope == .userAgent, !app.dryRun else { return }
        busyItems.insert(item.id)
        Task {
            _ = await Task.detached { LaunchItemScanner.setUserAgent(item, loaded: loaded) }.value
            await reloadLaunchItems()
            busyItems.remove(item.id)
        }
    }

    func remove(_ item: LaunchItem) {
        busyItems.insert(item.id)
        Task {
            var report = RemovalReport()
            report.wasSimulated = app.dryRun
            if app.dryRun {
                report.removedCount = 1
            } else if item.scope == .userAgent {
                do {
                    try LaunchItemScanner.removeUserAgent(item, dryRun: false)
                    report.removedCount = 1
                } catch {
                    report.failures.append(.init(path: item.plist.path(percentEncoded: false), reason: error.localizedDescription))
                }
            } else {
                let result = await app.privileged.run([
                    .bootout(label: item.label),
                    .moveToTrash(paths: [item.plist.path(percentEncoded: false)], uid: getuid()),
                ])
                if result.succeeded { report.removedCount = 1 } else {
                    report.failures.append(.init(path: item.plist.path(percentEncoded: false), reason: result.output))
                }
            }
            app.record(report, module: .performance)
            await reloadLaunchItems()
            busyItems.remove(item.id)
        }
    }

    private func reloadLaunchItems() async {
        let home = app.safetyGuard.home
        launchItems = await Task.detached { LaunchItemScanner(home: home).scan() }.value
    }

    /// Login items live in a database only root can read.
    func loadLoginItems() {
        loadingLoginItems = true
        loginItemsError = nil
        Task {
            let result = await app.privileged.run(.listBackgroundItems)
            if result.succeeded {
                loginItems = BackgroundTaskDump.parse(result.output).filter(\.isLoginItem)
            } else {
                loginItemsError = Self.describe(result)
            }
            loadingLoginItems = false
        }
    }

    func openLoginItemsSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
    }

    // MARK: Live usage

    func startMonitoring() {
        monitor?.cancel()
        monitor = Task {
            while !Task.isCancelled {
                await sample()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stopMonitoring() {
        monitor?.cancel()
        monitor = nil
    }

    private func sample() async {
        let (list, memory, ticks) = await Task.detached {
            (SystemMetrics.processes(), SystemMetrics.memory(), SystemMetrics.cpuTicks())
        }.value
        processes = Array(list.prefix(40))
        self.memory = memory
        if let old = lastTicks, let ticks { cpu = SystemMetrics.cpuUsage(from: old, to: ticks) }
        lastTicks = ticks
    }

    var heavyConsumers: [ProcessUsage] {
        Array(processes.filter { $0.cpu >= 1 || $0.memory > 500_000_000 }.prefix(15))
    }

    func quit(_ process: ProcessUsage) {
        NSRunningApplication(processIdentifier: process.pid)?.terminate()
        processes.removeAll { $0.pid == process.pid }
    }

    func appName(for process: ProcessUsage) -> (String, NSImage?) {
        if let running = NSRunningApplication(processIdentifier: process.pid) {
            return (running.localizedName ?? process.name, running.icon)
        }
        return (process.name, nil)
    }
}
