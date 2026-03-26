import SwiftUI

struct TerminalToolbar: View {
    let status: ProcessStatus
    let onStart: () -> Void
    let onStop: () -> Void
    let onRestart: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Status indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 12)

            Spacer()

            // Action buttons — icon only with tooltips
            HStack(spacing: 2) {
                Button(action: onStart) {
                    Image(systemName: "play.fill")
                        .frame(width: 28, height: 24)
                }
                .disabled(status == .running)
                .help("Start (Cmd+Shift+A)")

                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .frame(width: 28, height: 24)
                }
                .disabled(status == .stopped)
                .help("Stop (Cmd+Shift+S)")

                Button(action: onRestart) {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 28, height: 24)
                }
                .help("Restart (Cmd+Shift+R)")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12))
            .padding(.trailing, 8)
        }
        .frame(height: 32)
        .background(.bar)
    }

    private var statusColor: Color {
        switch status {
        case .running: return .green
        case .crashed: return .red
        case .crashLooping: return .orange
        case .stopped: return .gray
        }
    }

    private var statusLabel: String {
        switch status {
        case .running: return "Running"
        case .crashed: return "Crashed"
        case .crashLooping: return "Crash Loop"
        case .stopped: return "Stopped"
        }
    }
}
