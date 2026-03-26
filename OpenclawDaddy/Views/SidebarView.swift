import SwiftUI

struct SidebarView: View {
    let profiles: [Profile]
    let terminalIds: [UUID]
    let statusProvider: (UUID) -> ProcessStatus
    @Binding var selection: String?
    let onNewTerminal: () -> Void

    var body: some View {
        List(selection: $selection) {
            Section("Profiles") {
                ForEach(profiles) { profile in
                    HStack {
                        statusCircle(for: statusProvider(profile.id))
                        Text(profile.name)
                        Spacer()
                    }
                    .tag("profile-\(profile.id)")
                }
            }
            Section("Terminals") {
                ForEach(terminalIds, id: \.self) { id in
                    HStack {
                        Circle().fill(.gray.opacity(0.3)).frame(width: 8, height: 8)
                        Text("Shell \(id.uuidString.prefix(4))")
                        Spacer()
                    }
                    .tag("terminal-\(id)")
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button { onNewTerminal() } label: {
                    Label("New Terminal", systemImage: "plus.rectangle")
                }
                .buttonStyle(.plain).padding(8)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func statusCircle(for status: ProcessStatus) -> some View {
        Circle().fill(statusColor(status)).frame(width: 8, height: 8)
    }

    private func statusColor(_ status: ProcessStatus) -> Color {
        switch status {
        case .running: return .green
        case .crashed: return .red
        case .crashLooping: return .yellow
        case .stopped: return .gray
        }
    }
}
