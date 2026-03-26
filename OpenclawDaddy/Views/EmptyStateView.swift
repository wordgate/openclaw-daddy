import SwiftUI

struct EmptyStateView: View {
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No profiles configured")
                .font(.title2)
            Text("Add one in Settings or edit ~/.openclaw-daddy/config.yaml")
                .foregroundStyle(.secondary)
            Button("Open Settings") { onOpenSettings() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
