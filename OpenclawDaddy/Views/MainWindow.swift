import SwiftUI

struct MainWindow: View {
    @ObservedObject var configManager: ConfigManager
    @ObservedObject var processManager: ProcessManager
    var onCheckAppUpdate: () -> Void = {}
    @State private var selection: String? = "settings-general"
    @State private var terminalTabs: [TerminalTab] = []
    @State private var terminalFds: [UUID: Int32] = [:]
    @State private var showAddProfile = false
    @State private var newProfileName = ""
    @State private var updateAvailable = false
    @SceneStorage("selectedItem") private var savedSelection: String?

    @State private var keyMonitor: Any?

    var body: some View {
        NavigationSplitView {
            SidebarView(
                profiles: configManager.profiles,
                terminalTabs: terminalTabs,
                statusProvider: { processManager.status(for: $0) },
                selection: $selection,
                onNewTerminal: { spawnTerminal(title: "Shell") },
                onAddProfile: { showAddProfile = true },
                onCloseTerminal: closeTerminal,
                onStartProfile: { processManager.startProfile($0, openclawPath: configManager.config.openclawPath) },
                onStopProfile: { processManager.stopProfile($0) },
                onRestartProfile: { processManager.restartProfile($0, openclawPath: configManager.config.openclawPath) },
                onDeleteProfile: deleteProfile,
                hasUpdate: updateAvailable
            )
            .frame(minWidth: 180)
        } detail: {
            if let selection {
                detailView(for: selection)
            } else {
                detailView(for: "settings-general")
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .background(WindowAccessor())
        .onAppear {
            selection = savedSelection
            checkForUpdates()
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.modifierFlags.contains(.command),
                      !event.modifierFlags.contains(.shift),
                      !event.modifierFlags.contains(.option),
                      let char = event.characters,
                      let digit = Int(char), (1...9).contains(digit) else { return event }
                NotificationCenter.default.post(name: .switchToTab, object: nil, userInfo: ["index": digit - 1])
                return nil
            }
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
        .onChange(of: selection) { newValue in
            savedSelection = newValue
        }
        .sheet(isPresented: $showAddProfile) {
            AddProfileSheet(
                profileName: $newProfileName,
                existingNames: configManager.profiles.map(\.name),
                onAdd: { name in
                    addProfile(name: name)
                    showAddProfile = false
                    newProfileName = ""
                },
                onCancel: {
                    showAddProfile = false
                    newProfileName = ""
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .newTerminalRequested)) { _ in
            spawnTerminal(title: "Shell")
        }
        .onReceive(NotificationCenter.default.publisher(for: .addProfileRequested)) { _ in
            showAddProfile = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .restartSelectedRequested)) { _ in
            guard let sel = selection, sel.hasPrefix("profile-") else { return }
            let name = String(sel.dropFirst("profile-".count))
            processManager.restartProfile(Profile(name: name), openclawPath: configManager.config.openclawPath)
        }
        .onReceive(NotificationCenter.default.publisher(for: .stopSelectedRequested)) { _ in
            guard let sel = selection, sel.hasPrefix("profile-") else { return }
            let name = String(sel.dropFirst("profile-".count))
            processManager.stopProfile(name)
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeTabRequested)) { _ in
            guard let sel = selection, sel.hasPrefix("terminal-"),
                  let termId = extractTerminalId(from: sel) else { return }
            if processManager.isTerminalRunning(termId) {
                let alert = NSAlert()
                alert.messageText = "Close Terminal?"
                alert.informativeText = "The shell is still running."
                alert.addButton(withTitle: "Close")
                alert.addButton(withTitle: "Cancel")
                alert.alertStyle = .warning
                if alert.runModal() == .alertFirstButtonReturn {
                    closeTerminal(termId)
                }
            } else {
                closeTerminal(termId)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToTab)) { notification in
            guard let index = notification.userInfo?["index"] as? Int else { return }
            let allItems: [String] = configManager.profiles.map { "profile-\($0.name)" }
                + terminalTabs.map { "terminal-\($0.id)" }
            if index < allItems.count { selection = allItems[index] }
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectProfile)) { notification in
            guard let name = notification.userInfo?["profileName"] as? String else { return }
            selection = "profile-\(name)"
        }
    }

    // MARK: - Detail View

    @ViewBuilder
    private func detailView(for id: String) -> some View {
        if id == "settings-general" {
            GeneralSettingsView(
                configManager: configManager,
                onInstallOpenclaw: installOpenclaw,
                onUpdateOpenclaw: updateOpenclaw,
                onCheckAppUpdate: onCheckAppUpdate
            )
        } else if id == "settings-permissions" {
            PermissionsView()
        } else if id.hasPrefix("profile-") {
            profileDetailView(name: String(id.dropFirst("profile-".count)))
        } else if id.hasPrefix("terminal-"),
                  let termId = extractTerminalId(from: id),
                  let fd = terminalFds[termId] {
            TerminalView(masterFd: fd)
        }
    }

    @ViewBuilder
    private func profileDetailView(name: String) -> some View {
        let status = processManager.status(for: name)
        VStack(spacing: 0) {
            if let fd = processManager.masterFd(for: name), fd >= 0 {
                TerminalView(masterFd: fd)
            } else {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: status == .crashed || status == .crashLooping
                          ? "exclamationmark.triangle.fill" : "play.circle")
                        .font(.system(size: 40))
                        .foregroundStyle(status == .crashed ? .red : status == .crashLooping ? .orange : .secondary)
                    Text(name).font(.title3).fontWeight(.medium)
                    Text(status == .crashLooping ? "Crash-looping. Check openclaw config."
                         : status == .crashed ? "Process crashed."
                         : "Not running.")
                        .foregroundStyle(.secondary)
                    Button {
                        processManager.startProfile(Profile(name: name), openclawPath: configManager.config.openclawPath)
                    } label: {
                        Label("Start", systemImage: "play.fill").frame(minWidth: 80)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))
            }
            Divider()
            TerminalToolbar(
                status: status,
                onStart: { processManager.startProfile(Profile(name: name), openclawPath: configManager.config.openclawPath) },
                onStop: { processManager.stopProfile(name) },
                onRestart: { processManager.restartProfile(Profile(name: name), openclawPath: configManager.config.openclawPath) }
            )
        }
    }

    // MARK: - Terminal Spawning

    @discardableResult
    private func spawnTerminal(title: String, command: String? = nil) -> UUID? {
        let id = UUID()
        do {
            let pty: PTYProcess
            if let command {
                pty = try PTYManager.spawnShell(
                    shellCommand: command,
                    environment: ProcessInfo.processInfo.environment
                )
            } else {
                pty = try PTYManager.spawnInteractiveShell()
            }
            terminalTabs.append(TerminalTab(id: id, title: title))
            terminalFds[id] = pty.masterFd
            selection = "terminal-\(id)"
            return id
        } catch {
            return nil
        }
    }

    private func closeTerminal(_ id: UUID) {
        processManager.closeTerminal(id)
        terminalFds.removeValue(forKey: id)
        terminalTabs.removeAll { $0.id == id }
        selection = nil
    }

    // MARK: - Actions

    private func installOpenclaw() {
        spawnTerminal(
            title: "Installing openclaw",
            command: "curl -fsSL https://openclaw.ai/install.sh | bash"
        )
        // Re-detect openclaw after install likely finishes
        for delay in [10, 30, 60] {
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delay)) { [weak configManager] in
                guard let configManager else { return }
                if let detected = configManager.detectOpenclawPath() {
                    var config = configManager.config
                    config.openclawPath = detected
                    try? configManager.save(config)
                }
                configManager.scanProfiles()
            }
        }
    }

    private func updateOpenclaw() {
        let openclawPath = configManager.config.openclawPath
        updateAvailable = false

        // Stop all profiles, then update, then restart
        processManager.stopAll()

        spawnTerminal(
            title: "Updating openclaw",
            command: "\(openclawPath) update"
        )

        // Restart all profiles after update likely finishes
        for delay in [15, 30, 60] {
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delay)) {
                configManager.scanProfiles()
                startAllProfiles()
            }
        }
    }

    private func deleteProfile(_ name: String) {
        let alert = NSAlert()
        alert.messageText = "Delete profile \"\(name)\"?"
        alert.informativeText = "This will stop the process and remove ~/.openclaw-\(name)/. This cannot be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .critical
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        processManager.stopProfile(name)
        // Remove the profile directory
        let profileDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".openclaw-\(name)")
        try? FileManager.default.removeItem(at: profileDir)
        configManager.scanProfiles()
        if selection == "profile-\(name)" { selection = nil }
    }

    private func addProfile(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if configManager.profiles.contains(where: { $0.name == trimmed }) {
            let alert = NSAlert()
            alert.messageText = "Profile \"\(trimmed)\" already exists"
            alert.informativeText = "Choose a different name."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        spawnTerminal(
            title: "Setup: \(trimmed)",
            command: "\(configManager.config.openclawPath) --profile \(trimmed) onboard"
        )

        for delay in [3, 10, 30, 60] {
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delay)) { [weak configManager] in
                configManager?.scanProfiles()
            }
        }
    }

    private func checkForUpdates() {
        let path = configManager.config.openclawPath
        guard FileManager.default.isExecutableFile(atPath: path) else { return }

        DispatchQueue.global(qos: .utility).async {
            // `openclaw --version` outputs e.g. "OpenClaw 2026.3.24 (cff6dc9)"
            // Extract just the version number
            let rawVersion = runCommand(path, args: ["--version"])
            let current = rawVersion?
                .replacingOccurrences(of: "OpenClaw ", with: "")
                .components(separatedBy: " ").first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // `npm view openclaw@latest version` outputs e.g. "2026.3.24"
            let latest = runCommand("/usr/bin/env", args: ["npm", "view", "openclaw@latest", "version"])

            DispatchQueue.main.async {
                if let current, let latest, !current.isEmpty, !latest.isEmpty, current != latest {
                    updateAvailable = true
                } else {
                    updateAvailable = false
                }
            }
        }

        // Re-check every 6 hours
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(6 * 3600)) {
            checkForUpdates()
        }
    }

    private func startAllProfiles() {
        for profile in configManager.profiles {
            processManager.startProfile(profile, openclawPath: configManager.config.openclawPath)
        }
    }

    private func extractTerminalId(from selectionId: String) -> UUID? {
        guard let uuidString = selectionId.components(separatedBy: "terminal-").last else { return nil }
        return UUID(uuidString: uuidString)
    }
}

private func runCommand(_ path: String, args: [String]) -> String? {
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

// MARK: - Add Profile Sheet

struct AddProfileSheet: View {
    @Binding var profileName: String
    let existingNames: [String]
    let onAdd: (String) -> Void
    let onCancel: () -> Void

    private var trimmedName: String { profileName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isDuplicate: Bool { existingNames.contains(trimmedName) }
    private var isValid: Bool { !trimmedName.isEmpty && !isDuplicate }

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Profile").font(.headline)
            Text("Enter a name for the new openclaw profile.")
                .foregroundStyle(.secondary).font(.callout)
            TextField("Profile name (e.g. gateway)", text: $profileName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .onSubmit { if isValid { onAdd(trimmedName) } }
            if isDuplicate {
                Text("Profile \"\(trimmedName)\" already exists.")
                    .foregroundStyle(.red).font(.caption)
            }
            HStack {
                Button("Cancel", role: .cancel) { onCancel() }.keyboardShortcut(.escape)
                Button("Create") { onAdd(trimmedName) }
                    .disabled(!isValid)
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24).frame(width: 340)
    }
}

struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.setFrameAutosaveName("MainWindow") }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
