import ReviveKit
import SwiftUI

@MainActor @Observable
final class ActivityModel {
    private(set) var entries: [ActivityEntry] = []

    init() {
        Task { await reload() }
    }

    func reload() async {
        entries = await ActivityLog.shared.entries()
    }

    func clear() {
        Task {
            try? await ActivityLog.shared.clear()
            await reload()
        }
    }

    var realEntries: [ActivityEntry] { entries.filter { !$0.wasSimulated } }
    var totalFreed: Int64 { realEntries.reduce(0) { $0 + $1.freedBytes } }
    var totalItems: Int { realEntries.reduce(0) { $0 + $1.itemCount } }
}

struct ActivityView: View {
    let model: ActivityModel
    private let module = AppModule.myActivity

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text(module.title).screenTitle()
                Text(module.subtitle).screenSubtitle()
            }
            .padding(.top, 64)

            HStack(spacing: 16) {
                stat(value: formatBytes(model.totalFreed), label: "Space freed", symbol: "externaldrive.fill.badge.checkmark")
                stat(value: model.totalItems.formatted(), label: "Items removed", symbol: "trash.fill")
                stat(value: model.realEntries.count.formatted(), label: "Cleanups", symbol: "sparkles")
            }

            if model.entries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 40)).foregroundStyle(.white.opacity(0.6))
                    Text("Nothing yet. Run Smart Care or a cleanup and it will show up here.")
                        .font(.system(size: 15)).foregroundStyle(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.entries) { entry in
                            ActivityRow(entry: entry)
                        }
                    }
                    .padding(.bottom, 20)
                }
                HStack {
                    Spacer()
                    PillButton(title: "Clear History", symbol: "trash") { model.clear() }
                }
                .padding(.bottom, 20)
            }
        }
        .padding(.horizontal, 44)
        .task { await model.reload() }
    }

    private func stat(value: String, label: LocalizedStringResource, symbol: String) -> some View {
        HStack(spacing: 14) {
            FeatureBadge(symbol: symbol, theme: module.theme, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                Text(label).font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 20)
    }
}

private struct ActivityRow: View {
    let entry: ActivityEntry

    var body: some View {
        let module = AppModule(rawValue: entry.module) ?? .cleanup
        HStack(spacing: 14) {
            FeatureBadge(symbol: module.symbol, theme: module.theme, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(module.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                Text(entry.date, format: .dateTime.day().month().year().hour().minute())
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
            }
            if entry.wasSimulated {
                Text("Simulation")
                    .font(.system(size: 10, weight: .bold))
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(.white.opacity(0.15)))
            }
            Spacer()
            if entry.failureCount > 0 {
                Label("\(entry.failureCount)", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0xFFD43B))
                    .help("Items that could not be removed")
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatBytes(entry.freedBytes)).font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                Text("\(entry.itemCount) items").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassPanel(cornerRadius: 16)
    }
}
