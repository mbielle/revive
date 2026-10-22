import ReviveKit
import SwiftUI

/// Live numbers for the menu bar panel, sampled only while the panel is open.
@MainActor @Observable
final class MenuBarMonitor {
    private(set) var cpu: Double = 0
    private(set) var gpu: Double?
    private(set) var memory: MemoryUsage?
    private(set) var disk: DiskSpace?
    private(set) var battery: BatteryStatus?
    private(set) var download: Double = 0
    private(set) var upload: Double = 0

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var lastTicks: SystemMetrics.CPUTicks?
    @ObservationIgnored private var lastNetwork: (received: UInt64, sent: UInt64, date: Date)?

    func start() {
        task?.cancel()
        task = Task {
            while !Task.isCancelled {
                sample()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func sample() {
        if let ticks = SystemMetrics.cpuTicks() {
            if let lastTicks { cpu = SystemMetrics.cpuUsage(from: lastTicks, to: ticks) }
            lastTicks = ticks
        }
        memory = SystemMetrics.memory()
        gpu = SystemMetrics.gpuUsage()
        disk = SystemStatus.startupDisk()
        battery = SystemMetrics.battery()
        let network = SystemMetrics.networkBytes()
        let now = Date.now
        if let last = lastNetwork {
            let elapsed = max(now.timeIntervalSince(last.date), 0.1)
            download = Double(network.received &- last.received) / elapsed
            upload = Double(network.sent &- last.sent) / elapsed
        }
        lastNetwork = (network.received, network.sent, now)
    }
}

struct MenuBarPanel: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @State private var monitor = MenuBarMonitor()
    @State private var freeing = false
    private let theme = AppModule.smartCare.theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "infinity").font(.system(size: 16, weight: .bold))
                Text("Revive").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button {
                    open(.smartCare, start: false)
                } label: {
                    Text("Open").font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(.white.opacity(0.18)))
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                metric("CPU", value: percent(monitor.cpu), fraction: monitor.cpu, symbol: "cpu")
                metric("GPU", value: monitor.gpu.map(percent) ?? "—", fraction: monitor.gpu, symbol: "rectangle.3.group")
                metric("Memory", value: percent(monitor.memory?.usedFraction ?? 0), fraction: monitor.memory?.usedFraction ?? 0, symbol: "memorychip",
                       caption: monitor.memory.map { "\(formatBytes(Int64($0.used)))" })
                metric("Disk", value: monitor.disk.map { formatBytes($0.available) } ?? "—", fraction: monitor.disk?.usedFraction ?? 0,
                       symbol: "internaldrive", caption: "free")
            }

            HStack(spacing: 14) {
                Label("↓ \(rate(monitor.download))   ↑ \(rate(monitor.upload))", systemImage: "network")
                Spacer()
                if let battery = monitor.battery {
                    Label("\(Int(battery.level * 100))%", systemImage: battery.isCharging ? "battery.100percent.bolt" : "battery.75percent")
                }
            }
            .font(.system(size: 12, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.85))
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.1)))

            HStack(spacing: 8) {
                action("Smart Care", symbol: "sparkles") { open(.smartCare, start: true) }
                action("Protection", symbol: "checkmark.shield.fill") { open(.protection, start: true) }
                action("Free Up RAM", symbol: "memorychip", busy: freeing) {
                    freeing = true
                    Task {
                        await app.performance.runTasks([.freeMemory])
                        freeing = false
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(width: 330)
        .background { ModuleBackground(theme: theme) }
        .environment(\.colorScheme, .dark)
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }

    private func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    /// Brings the main window forward on a module, optionally starting its scan.
    private func open(_ module: AppModule, start: Bool) {
        app.selection = module
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        guard start else { return }
        switch module {
        case .smartCare where app.smartCare.phase == .idle: app.smartCare.scan()
        case .protection where app.protection.phase == .idle: app.protection.scan()
        default: break
        }
    }

    private func metric(_ title: LocalizedStringResource, value: String, fraction: Double?, symbol: String, caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .semibold)).textCase(.uppercase)
            }
            .foregroundStyle(.white.opacity(0.7))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit().contentTransition(.numericText())
                if let caption { Text(LocalizedStringKey(caption)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(1) }
            }
            if let fraction {
                GeometryReader { proxy in
                    Capsule().fill(.white.opacity(0.15))
                        .overlay(alignment: .leading) {
                            Capsule().fill(.white).frame(width: proxy.size.width * min(max(fraction, 0.02), 1))
                        }
                }
                .frame(height: 4)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.1)))
        .animation(.easeOut(duration: 0.4), value: value)
    }

    private func action(_ title: LocalizedStringResource, symbol: String, busy: Bool = false, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: 6) {
                if busy { ProgressView().controlSize(.small).tint(.white) } else { Image(systemName: symbol).font(.system(size: 16)) }
                Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.12)))
        }
        .buttonStyle(PressableStyle())
        .disabled(busy)
    }

    private func rate(_ bytesPerSecond: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s"
    }
}
