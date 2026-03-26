import SwiftUI

struct TerminalTab: Identifiable, Equatable {
    let id: UUID
    let title: String
}

struct SidebarView: View {
    let profiles: [Profile]
    let terminalTabs: [TerminalTab]
    let statusProvider: (String) -> ProcessStatus
    @Binding var selection: String?
    let onNewTerminal: () -> Void
    let onAddProfile: () -> Void
    let onCloseTerminal: (UUID) -> Void
    let onStartProfile: (Profile) -> Void
    let onStopProfile: (String) -> Void
    let onRestartProfile: (Profile) -> Void
    let onDeleteProfile: (String) -> Void
    var hasUpdate: Bool = false

    var body: some View {
        List(selection: $selection) {
            Section("Profiles") {
                ForEach(profiles) { profile in
                    let status = statusProvider(profile.name)
                    HStack(spacing: 8) {
                        statusIcon(status)
                        Text(profile.name).lineLimit(1)
                        Spacer()
                        if status == .crashed || status == .crashLooping {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                                .font(.caption2)
                        }
                    }
                    .tag("profile-\(profile.name)")
                    .contextMenu {
                        if status == .stopped || status == .crashed || status == .crashLooping {
                            Button("Start") { onStartProfile(profile) }
                        }
                        if status == .running {
                            Button("Stop") { onStopProfile(profile.name) }
                        }
                        Button("Restart") { onRestartProfile(profile) }
                        Divider()
                        Button("Delete Profile...", role: .destructive) { onDeleteProfile(profile.name) }
                    }
                }

                Button { onAddProfile() } label: {
                    Label("Add Profile", systemImage: "plus")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }

            Section("Terminals") {
                ForEach(terminalTabs) { tab in
                    HStack(spacing: 8) {
                        Image(systemName: "terminal")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(tab.title).lineLimit(1)
                        Spacer()
                    }
                    .tag("terminal-\(tab.id)")
                    .contextMenu {
                        Button("Close", role: .destructive) { onCloseTerminal(tab.id) }
                    }
                }

                Button { onNewTerminal() } label: {
                    Label("New Terminal", systemImage: "plus")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }

            Section("Settings") {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape").foregroundStyle(.secondary).font(.caption)
                    Text("General")
                    if hasUpdate {
                        Spacer()
                        Circle().fill(.red).frame(width: 6, height: 6)
                    }
                }
                .tag("settings-general")

                HStack(spacing: 8) {
                    Image(systemName: "lock.shield").foregroundStyle(.secondary).font(.caption)
                    Text("Permissions")
                }
                .tag("settings-permissions")
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                KaituPromoView()
                Text("Powered by openclaw · MIT · v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
                    .font(.system(size: 9))
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: ProcessStatus) -> some View {
        switch status {
        case .running:
            Image(systemName: "circle.fill").foregroundStyle(.green).font(.system(size: 8))
        case .crashed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red).font(.system(size: 10))
        case .crashLooping:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange).font(.system(size: 10))
        case .stopped:
            Image(systemName: "circle").foregroundStyle(.secondary).font(.system(size: 8))
        }
    }
}

/// Prominent kaitu.io promo with pulse animation
struct KaituPromoView: View {
    @State private var glowing = false

    var body: some View {
        Button {
            if let url = URL(string: "https://kaitu.io") {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 8) {
                Text("🚀")
                    .font(.system(size: 16))
                    .scaleEffect(glowing ? 1.2 : 1.0)
                VStack(alignment: .leading, spacing: 2) {
                    Text("开途加速器")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    Text("kaitu.io — 全球加速")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
                Spacer()
                Image(systemName: "arrow.up.right.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.0, green: 0.5, blue: 1.0),
                                Color(red: 0.2, green: 0.3, blue: 0.9)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .opacity(glowing ? 1.0 : 0.85)
            )
            .shadow(color: .blue.opacity(glowing ? 0.4 : 0.15), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                glowing = true
            }
        }
    }
}
