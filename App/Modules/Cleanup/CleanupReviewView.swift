import LucentKit
import SwiftUI

/// Detailed review of one category: rules on the left, their items on the right.
struct CleanupReviewView: View {
    @Bindable var model: CleanupModel
    let category: CleanupCategory
    @State private var selectedRuleID: String?

    private var rules: [RuleResult] { model.result.results(in: category) }
    private var currentRule: RuleResult? { rules.first { $0.id == selectedRuleID } ?? rules.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Button {
                    model.reviewing = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(.white.opacity(0.15)))
                }
                .buttonStyle(PressableStyle())
                .keyboardShortcut(.cancelAction)
                FeatureBadge(symbol: category.symbol, theme: model.module.theme, size: 34)
                Text(category.title).font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                CategorySwitcher(model: model, current: category) { selectedRuleID = nil }
            }
            .padding(.top, 62)

            HStack(alignment: .top, spacing: 16) {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(rules) { rule in
                            RuleRow(model: model, rule: rule, isSelected: rule.id == currentRule?.id) {
                                selectedRuleID = rule.id
                            }
                        }
                    }
                    .padding(10)
                }
                .frame(width: 330)
                .glassPanel(cornerRadius: 20)

                if let rule = currentRule {
                    ItemList(model: model, rule: rule)
                        .glassPanel(cornerRadius: 20)
                }
            }

            HStack {
                Spacer()
                Text("\(formatBytes(model.size(selectedIn: category))) selected in \(Text(category.title))")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                PillButton(title: "Done", symbol: "checkmark") { model.reviewing = nil }
            }
            .padding(.bottom, 22)
        }
        .padding(.horizontal, 32)
    }
}

/// Tabs to jump between the categories that found something.
private struct CategorySwitcher: View {
    let model: CleanupModel
    let current: CleanupCategory
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(CleanupCategory.allCases.filter { model.result.totalSize(in: $0) > 0 }) { category in
                Button {
                    model.reviewing = category
                    onChange()
                } label: {
                    Text(category.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(category == current ? .black.opacity(0.8) : .white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(category == current ? AnyShapeStyle(.white) : AnyShapeStyle(.clear)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(.white.opacity(0.12)))
    }
}

private struct RuleRow: View {
    let model: CleanupModel
    let rule: RuleResult
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CheckBox(state: model.state(of: rule.items)) { model.toggle(rule.items) }
            Image(systemName: rule.rule.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 20)
            Text(rule.rule.title.resolved)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
            Spacer(minLength: 6)
            Text(formatBytes(rule.totalSize))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 46)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(isSelected ? 0.16 : 0)))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

private struct ItemList: View {
    let model: CleanupModel
    let rule: RuleResult

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(rule.rule.title.resolved)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                Text(rule.rule.detail.resolved)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                if rule.rule.removal == .permanent {
                    Label("These files are deleted for good.", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xFFD43B))
                        .padding(.top, 2)
                }
            }
            .padding(18)

            Rectangle().fill(.white.opacity(0.1)).frame(height: 1)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rule.items) { item in
                        ItemRow(model: model, item: item)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ItemRow: View {
    let model: CleanupModel
    let item: CleanupItem
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            CheckBox(state: model.selection.contains(item.id) ? .on : .off) { model.toggle([item]) }
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path(percentEncoded: false)))
                .resizable()
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(item.url.deletingLastPathComponent().path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if let app = item.usedByRunningApp {
                Text("\(app) is open")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(.orange.opacity(0.45)))
                    .help("Quit the app before cleaning these files.")
            }
            if hovering {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.8))
                .help("Show in Finder")
            }
            Text(formatBytes(item.size) + (item.isSizeComplete ? "" : "+"))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 76, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
        .background(.white.opacity(hovering ? 0.06 : 0))
        .onHover { hovering = $0 }
    }
}
