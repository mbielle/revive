import AppKit
import LucentKit
import SwiftUI

@MainActor @Observable
final class SpaceLensModel {
    enum Phase: Equatable { case idle, scanning, ready, removing }

    enum Target: Hashable {
        case home, startupDisk, folder(URL)

        @MainActor
        func url(home: URL) -> URL {
            switch self {
            case .home: home
            case .startupDisk: URL(filePath: "/")
            case let .folder(url): url
            }
        }
    }

    private(set) var phase: Phase = .idle
    private(set) var itemsScanned = 0
    private(set) var currentPath = ""
    private(set) var root: FileNode?
    /// Ids of the folders opened from the root, last one is displayed.
    private(set) var path: [String] = []
    var selection: Set<String> = []
    var target: Target = .home
    private(set) var lastReport: RemovalReport?

    @ObservationIgnored unowned let app: AppModel
    @ObservationIgnored private var task: Task<Void, Never>?

    init(app: AppModel) {
        self.app = app
    }

    var current: FileNode? {
        guard let root else { return nil }
        return path.last.flatMap { root.node(withID: $0) } ?? root
    }

    /// Nodes from the root to the displayed folder, for the breadcrumb.
    var trail: [FileNode] {
        guard let root else { return [] }
        return [root] + path.compactMap { root.node(withID: $0) }
    }

    var selectedNodes: [FileNode] {
        guard let root else { return [] }
        return selection.compactMap { root.node(withID: $0) }
    }

    var selectedSize: Int64 { selectedNodes.reduce(0) { $0 + $1.size } }

    // MARK: Actions

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = String(localized: "Choose")
        if panel.runModal() == .OK, let url = panel.url {
            target = .folder(url)
        }
    }

    func scan() {
        task?.cancel()
        phase = .scanning
        itemsScanned = 0
        selection = []
        path = []
        let url = target.url(home: app.home)
        currentPath = url.path(percentEncoded: false)
        let onProgress: @Sendable (ScanProgress) -> Void = { [weak self] progress in
            Task { @MainActor in
                self?.itemsScanned = progress.itemCount
                self?.currentPath = progress.currentPath
            }
        }
        task = Task {
            do {
                let root = try await Task.detached(priority: .userInitiated) {
                    try await SpaceScanner().scan(url, progress: onProgress)
                }.value
                guard !Task.isCancelled else { return }
                self.root = root
                phase = .ready
            } catch {
                phase = .idle
            }
        }
    }

    func stop() {
        task?.cancel()
        phase = root == nil ? .idle : .ready
    }

    /// Direction of the last navigation, for the zoom transition.
    private(set) var wentDeeper = true

    func open(_ node: FileNode) {
        guard node.isDirectory, !node.children.isEmpty else { return }
        wentDeeper = true
        withAnimation(.smooth(duration: 0.5)) { path.append(node.id) }
    }

    func goUp(to node: FileNode) {
        guard node.id != current?.id else { return }
        wentDeeper = false
        withAnimation(.smooth(duration: 0.5)) {
            if node.id == root?.id {
                path = []
            } else if let index = path.firstIndex(of: node.id) {
                path = Array(path.prefix(through: index))
            }
        }
    }

    func toggle(_ node: FileNode) {
        if selection.contains(node.id) {
            selection.remove(node.id)
        } else {
            // Selecting a folder replaces any selection inside it, to avoid counting twice.
            selection = selection.filter { !$0.hasPrefix(node.id + "/") && !node.id.hasPrefix($0 + "/") }
            selection.insert(node.id)
        }
    }

    func canRemove(_ node: FileNode) -> Bool {
        app.safetyGuard.check(node.url, policy: .userInitiated).isAllowed
    }

    func removeSelection() {
        let nodes = selectedNodes
        guard !nodes.isEmpty, let root else { return }
        phase = .removing
        let items = nodes.map { CleanupItem(url: $0.url, ruleID: "space-lens", size: $0.size) }
        let remover = app.remover()
        task = Task {
            let report = await remover.remove(items, policy: .userInitiated)
            let failed = Set(report.failures.map { $0.path.count > 1 && $0.path.hasSuffix("/") ? String($0.path.dropLast()) : $0.path })
            let removedIDs = Set(nodes.map(\.id).filter { !failed.contains($0) })
            // In simulation mode the files are still there; leave the map untouched.
            if !report.wasSimulated {
                self.root = root.removing(removedIDs)
            }
            selection = []
            lastReport = report
            app.record(report, module: .spaceLens)
            path = path.filter { self.root?.node(withID: $0) != nil }
            phase = .ready
        }
    }

    func reset() {
        task?.cancel()
        root = nil
        path = []
        selection = []
        phase = .idle
    }
}
