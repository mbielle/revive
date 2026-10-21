import LucentKit
import SwiftUI

struct SpaceLensView: View {
    @Bindable var model: SpaceLensModel
    private let module = AppModule.spaceLens

    var body: some View {
        Group {
            switch model.phase {
            case .idle:
                ModuleLanding(module: module) {
                    TargetPicker(model: model)
                } action: {
                    ScanButton(title: "Scan", theme: module.theme) { model.scan() }
                }
            case .scanning:
                WorkingView(module: module, title: "Mapping your storage…", progress: nil, detail: model.currentPath,
                            stat: String(localized: "\(model.itemsScanned.formatted()) items")) { model.stop() }
            case .ready, .removing:
                if model.root != nil {
                    SpaceMapView(model: model)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.phase)
    }
}

private struct TargetPicker: View {
    @Bindable var model: SpaceLensModel

    var body: some View {
        HStack(spacing: 8) {
            choice(.home, title: "Home Folder", symbol: "house.fill")
            choice(.startupDisk, title: "Macintosh HD", symbol: "internaldrive.fill")
            if case let .folder(url) = model.target {
                choice(model.target, title: "\(url.lastPathComponent)", symbol: "folder.fill")
            }
            PillButton(title: "Choose…", symbol: "folder.badge.plus") { model.chooseFolder() }
        }
    }

    private func choice(_ target: SpaceLensModel.Target, title: LocalizedStringResource, symbol: String) -> some View {
        let selected = model.target == target
        return Button {
            model.target = target
        } label: {
            Label { Text(title) } icon: { Image(systemName: symbol) }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? .black.opacity(0.8) : .white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.15))))
        }
        .buttonStyle(PressableStyle())
    }
}

/// Bubble map of the current folder with its list of items.
private struct SpaceMapView: View {
    @Bindable var model: SpaceLensModel
    @State private var confirming = false
    private let theme = AppModule.spaceLens.theme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Breadcrumb(model: model)
                .padding(.top, 60)

            HStack(alignment: .top, spacing: 16) {
                if let current = model.current {
                    NodeList(model: model, node: current)
                        .frame(width: 360)
                        .glassPanel(cornerRadius: 20)
                    BubbleMap(model: model, node: current, theme: theme)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            HStack(spacing: 14) {
                PillButton(title: "New Scan", symbol: "arrow.counterclockwise") { model.reset() }
                if let report = model.lastReport, report.removedCount > 0 {
                    Text(report.wasSimulated ? "Simulated: \(formatBytes(report.freedBytes))" : "Moved \(formatBytes(report.freedBytes)) to the Trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
                if !model.selection.isEmpty {
                    Text("\(model.selection.count) selected · \(formatBytes(model.selectedSize))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    PillButton(title: "Deselect", symbol: "xmark") { model.selection = [] }
                }
                ScanButton(title: "Remove", theme: theme, diameter: 84, pulses: false) { confirming = true }
                    .disabled(model.selection.isEmpty || model.phase == .removing)
                    .opacity(model.selection.isEmpty ? 0.45 : 1)
            }
            .padding(.bottom, 18)
        }
        .padding(.horizontal, 28)
        .confirmationDialog("Move \(model.selection.count) items to the Trash?", isPresented: $confirming) {
            Button("Move to Trash", role: .destructive) { model.removeSelection() }
        } message: {
            Text("\(formatBytes(model.selectedSize)) will be moved to the Trash. You can restore them until you empty it.")
        }
    }
}

private struct Breadcrumb: View {
    let model: SpaceLensModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(model.trail.enumerated()), id: \.element.id) { index, node in
                if index > 0 {
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                }
                Button {
                    model.goUp(to: node)
                } label: {
                    Text(index == 0 ? rootName(node) : node.name)
                        .font(.system(size: index == model.trail.count - 1 ? 22 : 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(index == model.trail.count - 1 ? 1 : 0.7))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            }
            if let current = model.current {
                Text(formatBytes(current.size))
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.leading, 8)
            }
        }
    }

    private func rootName(_ node: FileNode) -> String {
        node.url.path(percentEncoded: false) == "/" ? "Macintosh HD" : node.name
    }
}

private struct NodeList: View {
    let model: SpaceLensModel
    let node: FileNode

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(node.children) { child in
                    NodeRow(model: model, node: child, parentSize: node.size)
                }
                if node.otherSize > 0 {
                    HStack {
                        Image(systemName: "ellipsis.circle").frame(width: 22)
                        Text("Smaller items")
                        Spacer()
                        Text(formatBytes(node.otherSize))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                }
            }
            .padding(8)
        }
    }
}

private struct NodeRow: View {
    let model: SpaceLensModel
    let node: FileNode
    let parentSize: Int64
    @State private var hovering = false

    var body: some View {
        let removable = model.canRemove(node)
        HStack(spacing: 10) {
            CheckBox(state: model.selection.contains(node.id) ? .on : .off) { model.toggle(node) }
                .disabled(!removable)
                .opacity(removable ? 1 : 0.3)
                .help(removable ? Text("Select") : Text("Protected by Lucent"))
            Image(nsImage: NSWorkspace.shared.icon(forFile: node.url.path(percentEncoded: false)))
                .resizable()
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(node.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                GeometryReader { proxy in
                    Capsule().fill(.white.opacity(0.12))
                        .overlay(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.7))
                                .frame(width: max(3, proxy.size.width * CGFloat(node.size) / CGFloat(max(parentSize, 1))))
                        }
                }
                .frame(height: 4)
            }
            Text(formatBytes(node.size))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 70, alignment: .trailing)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(node.isDirectory && !node.children.isEmpty ? 0.6 : 0))
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(hovering ? 0.08 : 0)))
        .contentShape(Rectangle())
        .onTapGesture { model.open(node) }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
        }
    }
}

/// Bubble chart of the children of a folder.
private struct BubbleMap: View {
    let model: SpaceLensModel
    let node: FileNode
    let theme: ModuleTheme
    @State private var hovered: String?

    private var shown: [FileNode] { Array(node.children.prefix(28)) }

    var body: some View {
        GeometryReader { proxy in
            let bubbles = BubbleLayout.layout(sizes: shown.map(\.size), in: proxy.size)
            ZStack(alignment: .topLeading) {
                ForEach(bubbles, id: \.index) { bubble in
                    let child = shown[bubble.index]
                    BubbleView(node: child, radius: bubble.radius, hue: Double(bubble.index) / Double(max(shown.count, 1)),
                               theme: theme, isHovered: hovered == child.id, isSelected: model.selection.contains(child.id))
                        .position(bubble.center)
                        .onHover { hovered = $0 ? child.id : (hovered == child.id ? nil : hovered) }
                        .onTapGesture {
                            if child.isDirectory && !child.children.isEmpty {
                                model.open(child)
                            } else if model.canRemove(child) {
                                model.toggle(child)
                            }
                        }
                        .help("\(child.name) — \(formatBytes(child.size))")
                }
            }
            .animation(.spring(duration: 0.5), value: node.id)
        }
        .id(node.id)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}

private struct BubbleView: View {
    let node: FileNode
    let radius: CGFloat
    let hue: Double
    let theme: ModuleTheme
    let isHovered: Bool
    let isSelected: Bool

    var body: some View {
        let tint = theme.glow.blend(Color(hex: 0x4FD1FF), hue * 0.6)
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [tint.blend(.white, 0.35).opacity(0.85), theme.button.opacity(0.55), theme.dark.opacity(0.6)],
                                     center: .init(x: 0.35, y: 0.3), startRadius: 1, endRadius: radius * 1.4))
            Circle()
                .strokeBorder(.white.opacity(isSelected ? 1 : isHovered ? 0.7 : 0.3), lineWidth: isSelected ? 3 : 1.2)
            if radius > 30 {
                VStack(spacing: 2) {
                    Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                        .font(.system(size: min(22, radius * 0.28)))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(node.name)
                        .font(.system(size: min(14, radius * 0.2), weight: .semibold))
                        .lineLimit(1)
                    Text(formatBytes(node.size))
                        .font(.system(size: min(12, radius * 0.17), weight: .medium, design: .rounded))
                        .opacity(0.8)
                }
                .foregroundStyle(.white)
                .frame(width: radius * 1.6)
            }
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white, theme.button)
                    .offset(x: radius * 0.62, y: -radius * 0.62)
            }
        }
        .frame(width: radius * 2, height: radius * 2)
        .shadow(color: theme.dark.opacity(0.5), radius: isHovered ? 16 : 8, y: 4)
        .scaleEffect(isHovered ? 1.04 : 1)
        .animation(.spring(duration: 0.25), value: isHovered)
        .contentShape(Circle())
    }
}
