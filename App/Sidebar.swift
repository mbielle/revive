import SwiftUI

struct Sidebar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Color.clear.frame(height: 44) // room for the window buttons
            ForEach(AppModule.mainModules) { module in
                SidebarItem(module: module, isSelected: app.selection == module) { app.selection = module }
            }
            Spacer(minLength: 20)
            ForEach(AppModule.footerModules) { module in
                SidebarItem(module: module, isSelected: app.selection == module) { app.selection = module }
            }
            Color.clear.frame(height: 10)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(.black.opacity(0.12))
    }
}

struct SidebarItem: View {
    let module: AppModule
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: module.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(iconStyle)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .frame(width: 26)
                Text(module.title)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(.white.opacity(isSelected ? 1 : module.plannedRelease == nil ? 0.92 : 0.6))
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 4)
                if let version = module.plannedRelease {
                    Image(systemName: "clock")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .help(Text("Coming in version \(version)"))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(isSelected ? 0.17 : hovering ? 0.07 : 0))
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                        }
                    }
                    .shadow(color: .black.opacity(isSelected ? 0.15 : 0), radius: 8, y: 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    private var iconStyle: AnyShapeStyle {
        if isSelected {
            AnyShapeStyle(LinearGradient(colors: [.white, module.theme.glow], startPoint: .top, endPoint: .bottom))
        } else {
            AnyShapeStyle(LinearGradient(colors: [.white, .white.opacity(0.72)], startPoint: .top, endPoint: .bottom))
        }
    }
}
