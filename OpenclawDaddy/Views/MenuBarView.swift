import SwiftUI

struct MenuBarView: View {
    let profiles: [Profile]
    let statusProvider: (UUID) -> ProcessStatus
    let onStartAll: () -> Void
    let onStopAll: () -> Void
    let onOpenWindow: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        ForEach(profiles) { profile in
            HStack {
                Circle().fill(statusColor(statusProvider(profile.id))).frame(width: 8, height: 8)
                Text(profile.name)
                Spacer()
                Text(statusLabel(statusProvider(profile.id)))
                    .foregroundStyle(.secondary).font(.caption)
            }
        }
        Divider()
        Button("Start All") { onStartAll() }
        Button("Stop All") { onStopAll() }
        Divider()
        Button("Open Window") { onOpenWindow() }
        Button("Settings...") { onOpenSettings() }
        Divider()
        Button("Quit") { onQuit() }
    }

    private func statusColor(_ status: ProcessStatus) -> Color {
        switch status {
        case .running: return .green
        case .crashed: return .red
        case .crashLooping: return .yellow
        case .stopped: return .gray
        }
    }

    private func statusLabel(_ status: ProcessStatus) -> String {
        switch status {
        case .running: return "Running"
        case .crashed: return "Crashed"
        case .crashLooping: return "Crash Loop"
        case .stopped: return "Stopped"
        }
    }
}
