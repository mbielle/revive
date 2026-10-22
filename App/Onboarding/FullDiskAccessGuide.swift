import SwiftUI

/// Explains why Full Disk Access is needed and walks the user through granting it.
struct FullDiskAccessGuide: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    private let theme = AppModule.smartCare.theme

    var body: some View {
        VStack(spacing: 22) {
            HeroIllustration(style: .squircle, symbol: "lock.open.fill", theme: theme, size: 150, animated: false)
                .padding(.top, 10)
            VStack(spacing: 8) {
                Text("Give Revive access to your files")
                    .font(.system(size: 24, weight: .semibold))
                Text("macOS hides Mail, Safari, the Trash and other app data from apps by default. With Full Disk Access, Revive can find junk there too. It never sends anything off your Mac.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 12) {
                step(1, "Click Open System Settings below.")
                step(2, "Turn on Revive in the Full Disk Access list. If it is missing, click + and pick Revive in Applications.")
                step(3, "Come back here: Revive detects the change automatically.")
            }
            .padding(18)
            .glassPanel(cornerRadius: 16)

            if app.hasFullDiskAccess {
                Label("Full Disk Access is on", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
            }

            HStack(spacing: 12) {
                PillButton(title: "Not Now") { dismiss() }
                Spacer()
                PillButton(title: "Check Again", symbol: "arrow.clockwise") { app.refreshAccess() }
                PillButton(title: "Open System Settings", symbol: "gearshape.fill", prominent: true) {
                    app.openFullDiskAccessSettings()
                }
            }
        }
        .foregroundStyle(.white)
        .padding(30)
        .frame(width: 540)
        .background { ModuleBackground(theme: theme) }
        .environment(\.colorScheme, .dark)
        .onChange(of: app.hasFullDiskAccess) { _, granted in
            if granted { dismiss() }
        }
    }

    private func step(_ number: Int, _ text: LocalizedStringResource) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .frame(width: 24, height: 24)
                .background(Circle().fill(.white.opacity(0.2)))
            Text(text)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
