import SwiftUI
import ServiceManagement

/// Inline General settings view shown in main window detail area
struct GeneralSettingsView: View {
    @ObservedObject var configManager: ConfigManager
    let onInstallOpenclaw: () -> Void
    let onUpdateOpenclaw: () -> Void
    let onCheckAppUpdate: () -> Void

    @State private var openclawPath: String = ""
    @State private var restartDelay: Int = 3
    @State private var hasUnsavedChanges = false
    @State private var saveError: String?
    @State private var currentVersion: String?
    @State private var latestVersion: String?
    @State private var checkingUpdate = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var updateAvailable: Bool {
        guard let current = currentVersion, let latest = latestVersion else { return false }
        return current != latest
    }

    var body: some View {
        Form {
            Section("openclaw") {
                HStack {
                    TextField("Path to openclaw", text: $openclawPath)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: openclawPath) { _ in hasUnsavedChanges = true }
                    Button("Detect") { detect() }
                        .controlSize(.small)
                }

                if FileManager.default.isExecutableFile(atPath: openclawPath) {
                    versionRow
                } else if !openclawPath.isEmpty {
                    notFoundRow
                } else {
                    installRow
                }
            }

            Section("Startup") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !newValue // revert on failure
                        }
                    }
            }

            Section("Keepalive") {
                Stepper("Restart delay: \(restartDelay)s", value: $restartDelay, in: 1...60)
                    .onChange(of: restartDelay) { _ in hasUnsavedChanges = true }
            }

            Section("About") {
                HStack {
                    Text("App Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
                        .foregroundStyle(.secondary)
                }
                Button("Check App Updates") { onCheckAppUpdate() }
                    .controlSize(.small)
            }

            Section {
                HStack {
                    if let error = saveError {
                        Text(error).foregroundStyle(.red).font(.caption).lineLimit(1)
                    }
                    Spacer()
                    if hasUnsavedChanges {
                        Text("Unsaved").foregroundStyle(.secondary).font(.caption)
                    }
                    Button("Revert") { reload() }.disabled(!hasUnsavedChanges)
                    Button("Save") { save() }
                        .keyboardShortcut("s")
                        .disabled(!hasUnsavedChanges)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            reload()
            checkForUpdates()
        }
    }

    // MARK: - Subviews

    private var versionRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                if let version = currentVersion {
                    Text("v\(version)").foregroundStyle(.secondary).font(.caption.monospaced())
                } else {
                    Text("Installed").foregroundStyle(.green).font(.caption)
                }
            }

            if updateAvailable, let latest = latestVersion {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill").foregroundStyle(.blue)
                        Text("openclaw update available: v\(latest)")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    Button("Update openclaw") { onUpdateOpenclaw() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            } else if checkingUpdate {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.small)
                    Text("Checking openclaw updates...").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Button("Check openclaw Updates") { checkForUpdates() }
                    .controlSize(.small)
            }
        }
    }

    private var notFoundRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                Text("Not found at this path").foregroundStyle(.red).font(.caption)
            }
            Button("Install openclaw") { onInstallOpenclaw() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }

    private var installRow: some View {
        Button("Install openclaw") { onInstallOpenclaw() }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
    }

    // MARK: - Logic

    private func detect() {
        if let path = configManager.detectOpenclawPath() {
            openclawPath = path
            hasUnsavedChanges = true
            checkForUpdates()
        }
    }

    private func reload() {
        openclawPath = configManager.config.openclawPath
        restartDelay = configManager.config.restartDelay
        hasUnsavedChanges = false
        saveError = nil

        if !FileManager.default.isExecutableFile(atPath: openclawPath) {
            detect()
        } else {
            fetchCurrentVersion()
        }
    }

    private func save() {
        var config = configManager.config
        config.openclawPath = openclawPath
        config.restartDelay = restartDelay
        do {
            try configManager.save(config)
            hasUnsavedChanges = false
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func fetchCurrentVersion() {
        let path = openclawPath
        DispatchQueue.global(qos: .utility).async {
            let raw = Self.runCommand(path, args: ["--version"])
            // "OpenClaw 2026.3.24 (cff6dc9)" → "2026.3.24"
            let version = raw?
                .replacingOccurrences(of: "OpenClaw ", with: "")
                .components(separatedBy: " ").first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                currentVersion = version
            }
        }
    }

    private func checkForUpdates() {
        let path = openclawPath
        guard FileManager.default.isExecutableFile(atPath: path) else { return }

        checkingUpdate = true
        fetchCurrentVersion()

        DispatchQueue.global(qos: .utility).async {
            // Try `npm view openclaw@latest version` for latest
            let latest = Self.runCommand("/usr/bin/env", args: ["npm", "view", "openclaw@latest", "version"])
            DispatchQueue.main.async {
                latestVersion = latest
                checkingUpdate = false
            }
        }
    }

    private static func runCommand(_ path: String, args: [String]) -> String? {
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        proc.environment = ProcessInfo.processInfo.environment
        do {
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0,
               let data = try? pipe.fileHandleForReading.readDataToEndOfFile(),
               let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty {
                return output
            }
        } catch {}
        return nil
    }
}
