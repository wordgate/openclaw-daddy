import SwiftUI

struct MainWindow: View {
    @State var configManager: ConfigManager
    @State var processManager: ProcessManager
    @State private var selection: String?
    @State private var terminalIds: [UUID] = []
    @State private var terminalFds: [UUID: Int32] = [:]
    @SceneStorage("selectedItem") private var savedSelection: String?

    var body: some View {
        NavigationSplitView {
            SidebarView(
                profiles: configManager.config.resolvedProfiles(),
                terminalIds: terminalIds,
                statusProvider: { processManager.status(for: $0) },
                selection: $selection,
                onNewTerminal: newTerminal
            )
            .frame(minWidth: 180)
        } detail: {
            if let selection {
                detailView(for: selection)
            } else {
                EmptyStateView {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .background(WindowAccessor())
        .onAppear {
            selection = savedSelection
            startAutoProfiles()
        }
        .onChange(of: selection) { _, newValue in
            savedSelection = newValue
        }
        .onReceive(NotificationCenter.default.publisher(for: .newTerminalRequested)) { _ in
            newTerminal()
        }
        .onReceive(NotificationCenter.default.publisher(for: .restartSelectedRequested)) { _ in
            guard let sel = selection, sel.hasPrefix("profile-"),
                  let profile = findProfile(from: sel) else { return }
            let path = configManager.buildPath(for: profile, global: configManager.config.global)
            processManager.restartProfile(profile, path: path)
        }
        .onReceive(NotificationCenter.default.publisher(for: .stopSelectedRequested)) { _ in
            guard let sel = selection, sel.hasPrefix("profile-"),
                  let profile = findProfile(from: sel) else { return }
            processManager.stopProfile(profile.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeTabRequested)) { _ in
            guard let sel = selection else { return }
            if sel.hasPrefix("terminal-"), let termId = extractTerminalId(from: sel) {
                if processManager.isTerminalRunning(termId) {
                    let alert = NSAlert()
                    alert.messageText = "Close Terminal?"
                    alert.informativeText = "The shell is still running. Are you sure you want to close it?"
                    alert.addButton(withTitle: "Close")
                    alert.addButton(withTitle: "Cancel")
                    alert.alertStyle = .warning
                    if alert.runModal() == .alertFirstButtonReturn {
                        processManager.closeTerminal(termId)
                        terminalFds.removeValue(forKey: termId)
                        terminalIds.removeAll { $0 == termId }
                        selection = nil
                    }
                } else {
                    processManager.closeTerminal(termId)
                    terminalFds.removeValue(forKey: termId)
                    terminalIds.removeAll { $0 == termId }
                    selection = nil
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToTab)) { notification in
            guard let index = notification.userInfo?["index"] as? Int else { return }
            let profiles = configManager.config.resolvedProfiles()
            let allItems: [String] = profiles.map { "profile-\($0.id)" } + terminalIds.map { "terminal-\($0)" }
            if index < allItems.count {
                selection = allItems[index]
            }
        }
    }

    @ViewBuilder
    private func detailView(for id: String) -> some View {
        if id.hasPrefix("profile-"), let profile = findProfile(from: id) {
            VStack(spacing: 0) {
                if let fd = processManager.masterFd(for: profile.id), fd >= 0 {
                    TerminalView(masterFd: fd)
                } else {
                    Text("Process not running")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .foregroundStyle(.secondary)
                }
                Divider()
                TerminalToolbar(
                    isProfile: true,
                    status: processManager.status(for: profile.id),
                    onStart: { startProfile(profile) },
                    onStop: { processManager.stopProfile(profile.id) },
                    onRestart: {
                        let path = configManager.buildPath(for: profile, global: configManager.config.global)
                        processManager.restartProfile(profile, path: path)
                    }
                )
            }
        } else if id.hasPrefix("terminal-"),
                  let termId = extractTerminalId(from: id),
                  let fd = terminalFds[termId] {
            VStack(spacing: 0) {
                TerminalView(masterFd: fd)
                Divider()
                TerminalToolbar(isProfile: false, status: .running, onStart: {}, onStop: {}, onRestart: {})
            }
        }
    }

    private func newTerminal() {
        if let (id, fd) = processManager.spawnTerminal() {
            terminalIds.append(id)
            terminalFds[id] = fd
            selection = "terminal-\(id)"
        }
    }

    private func startProfile(_ profile: Profile) {
        let path = configManager.buildPath(for: profile, global: configManager.config.global)
        processManager.startProfile(profile, path: path)
    }

    private func startAutoProfiles() {
        for profile in configManager.config.resolvedProfiles() where profile.autostart {
            startProfile(profile)
        }
    }

    private func findProfile(from selectionId: String) -> Profile? {
        guard let uuidString = selectionId.components(separatedBy: "profile-").last,
              let uuid = UUID(uuidString: uuidString) else { return nil }
        return configManager.config.resolvedProfiles().first { $0.id == uuid }
    }

    private func extractTerminalId(from selectionId: String) -> UUID? {
        guard let uuidString = selectionId.components(separatedBy: "terminal-").last else { return nil }
        return UUID(uuidString: uuidString)
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
