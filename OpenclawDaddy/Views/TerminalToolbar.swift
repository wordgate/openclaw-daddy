import SwiftUI

struct TerminalToolbar: View {
    let isProfile: Bool
    let status: ProcessStatus
    let onStart: () -> Void
    let onStop: () -> Void
    let onRestart: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if isProfile {
                Button(action: onStart) { Label("Start", systemImage: "play.fill") }
                    .disabled(status == .running)
                Button(action: onStop) { Label("Stop", systemImage: "stop.fill") }
                    .disabled(status == .stopped)
                Button(action: onRestart) { Label("Restart", systemImage: "arrow.clockwise") }
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}
