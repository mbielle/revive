import LucentKit
import SwiftUI

struct ClutterView: View {
    @Bindable var model: ClutterModel
    private let module = AppModule.myClutter

    var body: some View {
        Group {
            switch model.phase {
            case .idle:
                ModuleLanding(module: module) {
                    ScanButton(title: "Scan", theme: module.theme) { model.scan() }
                }
            case .scanning:
                WorkingView(module: module, title: "Looking for clutter…", progress: nil, detail: model.progress.currentPath,
                            stat: String(localized: "\(model.progress.itemCount.formatted()) files")) { model.stop() }
            case .ready, .removing:
                switch model.section {
                case nil: overview
                case let .some(section): ClutterSectionScreen(model: model, section: section)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.phase)
        .animation(.easeInOut(duration: 0.3), value: model.section)
    }

    private var overview: some View {
        let r = model.result
        let total = r.duplicates.reduce(0) { $0 + $1.reclaimable } + r.similarPhotos.reduce(0) { $0 + $1.reclaimable }
        return OverviewScreen(
            title: String(localized: "\(formatBytes(total)) of duplicates and similar photos"),
            subtitle: String(localized: "Plus \(r.largeOldFiles.count) large or forgotten files and \(r.screenshots.count) screenshots to look at.")
        ) {
            OverviewTile(symbol: "doc.on.doc.fill", title: "Duplicates", subtitle: r.duplicates.count == 1 ? String(localized: "1 file with identical copies.") : String(localized: "\(r.duplicates.count) files with identical copies."),
                         value: formatBytes(r.duplicates.reduce(0) { $0 + $1.reclaimable }), theme: module.theme) { model.section = .duplicates }
            OverviewTile(symbol: "photo.on.rectangle.angled", title: "Similar Photos", subtitle: r.similarPhotos.count == 1 ? String(localized: "1 group of look-alike shots.") : String(localized: "\(r.similarPhotos.count) groups of look-alike shots."),
                         value: formatBytes(r.similarPhotos.reduce(0) { $0 + $1.reclaimable }), theme: module.theme) { model.section = .similar }
            OverviewTile(symbol: "shippingbox.fill", title: "Large & Old Files", subtitle: String(localized: "Big files and files untouched for a year."),
                         value: formatBytes(r.largeOldFiles.reduce(0) { $0 + $1.size }), theme: module.theme) { model.section = .large }
            OverviewTile(symbol: "camera.viewfinder", title: "Screenshots", subtitle: String(localized: "Screenshots piling up on your Desktop."),
                         value: "\(r.screenshots.count)", theme: module.theme) { model.section = .screenshots }
        } footer: {
            HStack(spacing: 14) {
                PillButton(title: "Scan Again", symbol: "arrow.counterclockwise") { model.scan() }
                if let report = model.lastReport, report.removedCount > 0 {
                    Text(report.wasSimulated ? "Simulated: \(formatBytes(report.freedBytes))" : "Moved \(formatBytes(report.freedBytes)) to the Trash")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                }
            }
        }
    }
}

private struct ClutterSectionScreen: View {
    @Bindable var model: ClutterModel
    let section: ClutterModel.Section
    @State private var confirming = false
    private let theme = AppModule.myClutter.theme

    var body: some View {
        DetailScreen(title: title, symbol: symbol, theme: theme, onBack: { model.section = nil }) {
            EmptyView()
        } content: {
            Text(explanation).font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
            ScrollView {
                switch section {
                case .duplicates: groups(model.result.duplicates, thumbnails: false)
                case .similar: groups(model.result.similarPhotos, thumbnails: true)
                case .large: list(model.result.largeOldFiles)
                case .screenshots: grid(model.result.screenshots)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay { if model.files(in: section).isEmpty { EmptyState(symbol: "checkmark.circle.fill", message: "Nothing here. Nice and tidy.") } }
        } bottom: {
            HStack(spacing: 16) {
                Spacer()
                if model.selectedCount(in: section) > 0 {
                    Text("\(model.selectedCount(in: section)) selected · \(formatBytes(model.selectedSize(in: section)))")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                }
                ScanButton(title: "Remove", theme: theme, diameter: 84, pulses: false) { confirming = true }
                    .disabled(model.selectedCount(in: section) == 0 || model.phase == .removing)
                    .opacity(model.selectedCount(in: section) == 0 ? 0.45 : 1)
            }
        }
        .confirmationDialog("Move \(model.selectedCount(in: section)) files to the Trash?", isPresented: $confirming) {
            Button("Move to Trash", role: .destructive) { model.removeSelected(in: section) }
        } message: {
            Text("These are your own files. You can restore them from the Trash until you empty it.")
        }
    }

    private var title: LocalizedStringResource {
        switch section {
        case .duplicates: "Duplicates"
        case .similar: "Similar Photos"
        case .large: "Large & Old Files"
        case .screenshots: "Screenshots"
        }
    }

    private var symbol: String {
        switch section {
        case .duplicates: "doc.on.doc.fill"
        case .similar: "photo.on.rectangle.angled"
        case .large: "shippingbox.fill"
        case .screenshots: "camera.viewfinder"
        }
    }

    private var explanation: LocalizedStringResource {
        switch section {
        case .duplicates: "Identical files, byte for byte. The oldest copy of each is kept unchecked."
        case .similar: "Photos that look alike, usually bursts or retakes. The largest of each group is kept unchecked."
        case .large: "Files over 50 MB, and files over 10 MB nobody opened for a year. Nothing is checked: decide one by one."
        case .screenshots: "Screenshots from your Desktop, Downloads and Pictures, oldest first."
        }
    }

    private func groups(_ groups: [ClutterGroup], thumbnails: Bool) -> some View {
        LazyVStack(spacing: 12) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(group.files.first?.url.lastPathComponent ?? "").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        Spacer()
                        Text("\(group.files.count) copies · \(formatBytes(group.reclaimable)) to free")
                            .font(.system(size: 12, design: .rounded)).foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)
                    if thumbnails {
                        ScrollView(.horizontal) {
                            HStack(spacing: 10) {
                                ForEach(Array(group.files.enumerated()), id: \.element.id) { index, file in
                                    PhotoTile(file: file, isSelected: model.selection.contains(file.id), isBest: index == 0) { model.toggle(file) }
                                }
                            }
                            .padding(.horizontal, 16).padding(.bottom, 12)
                        }
                    } else {
                        ForEach(Array(group.files.enumerated()), id: \.element.id) { index, file in
                            FileItemRow(item: file.asCleanupItem, isSelected: model.selection.contains(file.id),
                                        note: index == 0 ? String(localized: "Original · \(parent(file))") : parent(file)) { model.toggle(file) }
                        }
                    }
                }
                .glassPanel(cornerRadius: 16)
            }
        }
    }

    private func list(_ files: [ClutterFile]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(files) { file in
                FileItemRow(item: file.asCleanupItem, isSelected: model.selection.contains(file.id), note: note(file)) { model.toggle(file) }
            }
        }
        .padding(.vertical, 6)
        .glassPanel(cornerRadius: 20)
    }

    private func grid(_ files: [ClutterFile]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
            ForEach(files) { file in
                PhotoTile(file: file, isSelected: model.selection.contains(file.id), isBest: false) { model.toggle(file) }
            }
        }
        .padding(12)
        .glassPanel(cornerRadius: 20)
    }

    private func parent(_ file: ClutterFile) -> String {
        file.url.deletingLastPathComponent().path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private func note(_ file: ClutterFile) -> String {
        let date = (file.accessed ?? file.modified).map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—"
        return String(localized: "\(parent(file)) · last used \(date)")
    }
}

private struct PhotoTile: View {
    let file: ClutterFile
    let isSelected: Bool
    let isBest: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Thumbnail(url: file.url, size: 130)
                .overlay(alignment: .topLeading) {
                    CheckBox(state: isSelected ? .on : .off, action: toggle).padding(6)
                }
                .overlay(alignment: .bottomLeading) {
                    if isBest {
                        Text("Best").font(.system(size: 10, weight: .bold)).foregroundStyle(.black.opacity(0.8))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color(hex: 0xFFD43B))).padding(6)
                    }
                }
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(isSelected ? 0.9 : 0), lineWidth: 2) }
            Text(file.url.lastPathComponent).font(.system(size: 11)).foregroundStyle(.white.opacity(0.8)).lineLimit(1).frame(width: 130, alignment: .leading)
            Text(formatBytes(file.size)).font(.system(size: 10, design: .rounded)).foregroundStyle(.white.opacity(0.55))
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .contextMenu { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) } }
    }
}
