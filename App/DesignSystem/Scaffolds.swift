import ReviveKit
import SwiftUI

/// Summary screen after a scan: title, subtitle and a grid of tiles that open detail screens.
struct OverviewScreen<Tiles: View, Footer: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var tiles: Tiles
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text(title).screenTitle()
                Text(subtitle).screenSubtitle()
            }
            .multilineTextAlignment(.center)
            .padding(.top, 70)
            .padding(.horizontal, 40)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)], spacing: 18) {
                tiles
            }
            .frame(maxWidth: 780)
            .padding(.horizontal, 40)
            .padding(.top, 30)

            Spacer(minLength: 20)
            footer.padding(.bottom, 34)
        }
    }
}

/// A clickable tile of an overview screen.
struct OverviewTile: View {
    let symbol: String
    let title: LocalizedStringResource
    let subtitle: String
    let value: String
    let theme: ModuleTheme
    var badge: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                FeatureBadge(symbol: symbol, theme: theme, size: 46)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.85)
                        if let badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.black.opacity(0.8))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Color(hex: 0xFFD43B)))
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(value)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .fixedSize()
                    Text("Review \(Image(systemName: "chevron.right"))")
                        .lineLimit(1)
                        .fixedSize()
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(hovering ? 1 : 0.7))
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 92)
            .glassPanel(cornerRadius: 20)
            .scaleEffect(hovering ? 1.015 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.25), value: hovering)
    }
}

/// Detail screen with a back button, a title and optional trailing controls.
struct DetailScreen<Trailing: View, Content: View, Bottom: View>: View {
    let title: LocalizedStringResource
    let symbol: String
    let theme: ModuleTheme
    let onBack: () -> Void
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content
    @ViewBuilder var bottom: Bottom

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                BackButton(action: onBack)
                FeatureBadge(symbol: symbol, theme: theme, size: 34)
                Text(title).font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                trailing
            }
            .padding(.top, 62)
            content
            bottom.padding(.bottom, 18)
        }
        .padding(.horizontal, 32)
    }
}

struct BackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(.white.opacity(0.15)))
        }
        .buttonStyle(PressableStyle())
        .keyboardShortcut(.cancelAction)
    }
}

/// Pill-shaped segmented control for dark gradients.
struct PillPicker<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.0) { value, label in
                Button {
                    selection = value
                } label: {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selection == value ? .black.opacity(0.8) : .white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(selection == value ? AnyShapeStyle(.white) : AnyShapeStyle(.clear)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(.white.opacity(0.12)))
    }
}

/// Search field styled for dark gradients.
struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.6))
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12).padding(.vertical, 7)
        .frame(width: 200)
        .background(Capsule().fill(.white.opacity(0.12)))
    }
}

/// A file or folder row with a checkbox, used by every list of removable items.
struct FileItemRow: View {
    let item: CleanupItem
    let isSelected: Bool
    var note: String?
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            CheckBox(state: isSelected ? .on : .off, action: toggle)
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path(percentEncoded: false)))
                .resizable()
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(note ?? item.url.deletingLastPathComponent().path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
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
            Text(formatBytes(item.size))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 76, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(.white.opacity(hovering ? 0.06 : 0))
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .onHover { hovering = $0 }
    }
}

/// Empty list placeholder.
struct EmptyState: View {
    let symbol: String
    let message: LocalizedStringResource

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 38)).foregroundStyle(.white.opacity(0.6))
            Text(message).font(.system(size: 15)).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
