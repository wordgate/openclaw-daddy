import SwiftUI

struct PermissionsView: View {
    @StateObject var permissionManager = PermissionManager()

    var body: some View {
        Form {
            Section("Permissions") {
                ForEach(permissionManager.permissions) { perm in
                    HStack {
                        statusIcon(perm.status)
                        Text(perm.name)
                        Spacer()
                        Text(perm.status.rawValue).foregroundStyle(.secondary).font(.caption)
                        if perm.canRequest && (perm.status == .notAsked || perm.status == .denied) {
                            Button("Request") { permissionManager.request(perm.id) }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                        if let url = perm.settingsURL {
                            Button("Open Settings") { permissionManager.openSettings(url) }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
            }
            Section {
                Button("Open System Settings") {
                    permissionManager.openSettings("x-apple.systempreferences:com.apple.preference.security")
                }
                Button("Refresh") { permissionManager.refresh() }
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionManager.refresh()
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: PermissionStatus) -> some View {
        switch status {
        case .granted: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .denied: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .notAsked: Image(systemName: "circle").foregroundStyle(.gray)
        case .unknown: Image(systemName: "questionmark.circle.fill").foregroundStyle(.orange)
        }
    }
}
