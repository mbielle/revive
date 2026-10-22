import ReviveKit
import SwiftUI

/// Shortcuts the user pins to the My Tools screen.
enum Tool: String, CaseIterable, Identifiable {
    case smartCare, systemJunk, trashBins, freeUpRAM, flushDNS, uninstaller, updater, leftovers
    case spaceLens, duplicates, similarPhotos, largeFiles, malwareScan, privacy, permissions
    case backgroundItems, heavyConsumers, cloud

    var id: String { rawValue }

    static let defaultPinned: [Tool] = [.freeUpRAM, .uninstaller, .updater, .spaceLens, .duplicates, .malwareScan]

    var title: LocalizedStringResource {
        switch self {
        case .smartCare: "Smart Care"
        case .systemJunk: "System Junk"
        case .trashBins: "Trash Bins"
        case .freeUpRAM: "Free Up RAM"
        case .flushDNS: "Flush DNS Cache"
        case .uninstaller: "Uninstaller"
        case .updater: "Updater"
        case .leftovers: "Leftovers"
        case .spaceLens: "Space Lens"
        case .duplicates: "Duplicates"
        case .similarPhotos: "Similar Photos"
        case .largeFiles: "Large & Old Files"
        case .malwareScan: "Malware Removal"
        case .privacy: "Privacy Check"
        case .permissions: "Application Permissions"
        case .backgroundItems: "Background Items"
        case .heavyConsumers: "Heavy Consumers"
        case .cloud: "Cloud Cleanup"
        }
    }

    var symbol: String {
        switch self {
        case .smartCare: "desktopcomputer"
        case .systemJunk: "xmark.bin.fill"
        case .trashBins: "trash.fill"
        case .freeUpRAM: "memorychip"
        case .flushDNS: "network"
        case .uninstaller: "xmark.app.fill"
        case .updater: "arrow.down.app.fill"
        case .leftovers: "puzzlepiece.extension.fill"
        case .spaceLens: "circle.hexagongrid.fill"
        case .duplicates: "doc.on.doc.fill"
        case .similarPhotos: "photo.on.rectangle.angled"
        case .largeFiles: "shippingbox.fill"
        case .malwareScan: "ladybug.fill"
        case .privacy: "lock.shield.fill"
        case .permissions: "lock.open.fill"
        case .backgroundItems: "gearshape.2.fill"
        case .heavyConsumers: "gauge.with.dots.needle.67percent"
        case .cloud: "cloud.fill"
        }
    }

    var module: AppModule {
        switch self {
        case .smartCare: .smartCare
        case .systemJunk, .trashBins: .cleanup
        case .freeUpRAM, .flushDNS, .backgroundItems, .heavyConsumers: .performance
        case .uninstaller, .updater, .leftovers: .applications
        case .spaceLens: .spaceLens
        case .duplicates, .similarPhotos, .largeFiles: .myClutter
        case .malwareScan, .privacy, .permissions: .protection
        case .cloud: .cloudCleanup
        }
    }

    /// Opens the tool, starting its module's scan when needed.
    @MainActor
    func open(in app: AppModel) {
        app.selection = module
        switch self {
        case .smartCare: if app.smartCare.phase == .idle { app.smartCare.scan() }
        case .systemJunk, .trashBins:
            if app.cleanup.phase == .idle { app.cleanup.scan() }
            app.cleanup.pendingReview = self == .trashBins ? .trashBins : .systemJunk
        case .freeUpRAM: Task { await app.performance.runTasks([.freeMemory]) }
        case .flushDNS: Task { await app.performance.runTasks([.flushDNS]) }
        case .backgroundItems: app.performance.open(.backgroundItems)
        case .heavyConsumers: app.performance.open(.consumers)
        case .uninstaller: app.applications.open(.uninstaller)
        case .updater: app.applications.openUpdater()
        case .leftovers: app.applications.open(.leftovers)
        case .spaceLens: if app.spaceLens.phase == .idle { app.spaceLens.scan() }
        case .duplicates: app.clutter.open(.duplicates)
        case .similarPhotos: app.clutter.open(.similar)
        case .largeFiles: app.clutter.open(.large)
        case .malwareScan: app.protection.open(.malware)
        case .privacy: app.protection.open(.privacy)
        case .permissions: app.protection.open(.permissions)
        case .cloud: if app.cloud.phase == .idle { app.cloud.scan() }
        }
    }
}

@MainActor @Observable
final class ToolsModel {
    var pinned: [Tool] {
        didSet { UserDefaults.standard.set(pinned.map(\.rawValue), forKey: "pinnedTools") }
    }
    var isEditing = false

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: "pinnedTools")?.compactMap(Tool.init(rawValue:))
        pinned = saved ?? Tool.defaultPinned
    }

    func togglePin(_ tool: Tool) {
        if let index = pinned.firstIndex(of: tool) { pinned.remove(at: index) } else { pinned.append(tool) }
    }
}

struct ToolsView: View {
    @Bindable var model: ToolsModel
    @Environment(AppModel.self) private var app
    private let module = AppModule.myTools

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(module.title).screenTitle()
                    Text(module.subtitle).screenSubtitle()
                }
                Spacer()
                PillButton(title: model.isEditing ? "Done" : "Customize", symbol: model.isEditing ? "checkmark" : "slider.horizontal.3") {
                    withAnimation(.spring(duration: 0.35)) { model.isEditing.toggle() }
                }
            }
            .padding(.top, 64)

            ScrollView {
                if model.isEditing {
                    Text("Click a tool to pin or unpin it.").font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 16)], spacing: 16) {
                    ForEach(model.isEditing ? Tool.allCases : model.pinned) { tool in
                        ToolCard(tool: tool, isPinned: model.pinned.contains(tool), isEditing: model.isEditing) {
                            if model.isEditing { model.togglePin(tool) } else { tool.open(in: app) }
                        }
                    }
                }
                // Room for the hover zoom: the scroll view would otherwise clip the cards' edges.
                .padding(10)
                .padding(.bottom, 14)
            }
            .scrollClipDisabled()
            .padding(-10)
            .overlay {
                if model.pinned.isEmpty && !model.isEditing {
                    EmptyState(symbol: "pin", message: "No pinned tools. Click Customize to add some.")
                }
            }
        }
        .padding(.horizontal, 44)
    }
}

private struct ToolCard: View {
    let tool: Tool
    let isPinned: Bool
    let isEditing: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    FeatureBadge(symbol: tool.symbol, theme: tool.module.theme, size: 46)
                    Spacer()
                    if isEditing {
                        Image(systemName: isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(isPinned ? Color(hex: 0xFFD43B) : .white.opacity(0.6))
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(tool.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    Text(tool.module.title).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [tool.module.theme.light.opacity(0.45), tool.module.theme.dark.opacity(0.35)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .glassPanel(cornerRadius: 20)
            .opacity(isEditing && !isPinned ? 0.6 : 1)
            .scaleEffect(hovering ? 1.03 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.25), value: hovering)
    }
}
