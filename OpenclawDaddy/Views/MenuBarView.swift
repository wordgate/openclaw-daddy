import SwiftUI

struct MenuBarView: View {
    let profiles: [Profile]
    let statusProvider: (String) -> ProcessStatus
    let onStartProfile: (Profile) -> Void
    let onStopProfile: (String) -> Void
    let onStartAll: () -> Void
    let onStopAll: () -> Void
    let onOpenWindow: () -> Void
    let onQuit: () -> Void

    var body: some View {
        if profiles.isEmpty {
            Text("No profiles found")
                .foregroundStyle(.secondary)
        } else {
            ForEach(profiles) { profile in
                let status = statusProvider(profile.name)
                Button {
                    onOpenWindow()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NotificationCenter.default.post(
                            name: .selectProfile,
                            object: nil,
                            userInfo: ["profileName": profile.name]
                        )
                    }
                } label: {
                    HStack {
                        Image(systemName: statusIcon(status))
                            .foregroundStyle(statusColor(status))
                        Text(profile.name)
                        Spacer()
                        Text(status.rawValue.capitalized)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }
        }

        Divider()
        Button("Start All") { onStartAll() }
        Button("Stop All") { onStopAll() }
        Divider()
        Button("Open Window") { onOpenWindow() }
        Divider()
        Button("Quit OpenclawDaddy") { onQuit() }
    }

    private func statusIcon(_ s: ProcessStatus) -> String {
        switch s {
        case .running: return "circle.fill"
        case .crashed: return "xmark.circle.fill"
        case .crashLooping: return "exclamationmark.circle.fill"
        case .stopped: return "circle"
        }
    }

    private func statusColor(_ s: ProcessStatus) -> Color {
        switch s {
        case .running: return .green
        case .crashed: return .red
        case .crashLooping: return .orange
        case .stopped: return .gray
        }
    }
}
