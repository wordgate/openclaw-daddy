import SwiftUI
import UserNotifications

extension Notification.Name {
    static let newTerminalRequested = Notification.Name("newTerminalRequested")
    static let restartSelectedRequested = Notification.Name("restartSelectedRequested")
    static let stopSelectedRequested = Notification.Name("stopSelectedRequested")
    static let closeTabRequested = Notification.Name("closeTabRequested")
    static let addProfileRequested = Notification.Name("addProfileRequested")
    static let switchToTab = Notification.Name("switchToTab")
}

@main
struct OpenclawDaddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var configManager = ConfigManager()
    @State private var processManager = ProcessManager()

    var body: some Scene {
        WindowGroup {
            MainWindow(
                configManager: configManager,
                processManager: processManager
            )
            .onAppear {
                do {
                    let config = try configManager.load()
                    processManager = ProcessManager(restartDelay: config.global.restartDelay)
                    configManager.startWatching()
                } catch {
                    print("Config load error: \(error)")
                }
                appDelegate.processManager = processManager
                processManager.onCrashLoop = { _, name in
                    let content = UNMutableNotificationContent()
                    content.title = "OpenclawDaddy"
                    content.body = "\(name) is crash-looping"
                    content.sound = .default
                    let request = UNNotificationRequest(identifier: "crash-loop-\(name)", content: content, trigger: nil)
                    UNUserNotificationCenter.current().add(request)
                }
            }
        }
        .defaultSize(width: 1000, height: 600)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Terminal") {
                    NotificationCenter.default.post(name: .newTerminalRequested, object: nil)
                }.keyboardShortcut("t")
                Button("New Profile") {
                    NotificationCenter.default.post(name: .addProfileRequested, object: nil)
                }.keyboardShortcut("n")
                Button("Close Tab") {
                    NotificationCenter.default.post(name: .closeTabRequested, object: nil)
                }.keyboardShortcut("w")
            }
            CommandGroup(after: .toolbar) {
                Button("Restart Selected") {
                    NotificationCenter.default.post(name: .restartSelectedRequested, object: nil)
                }.keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Stop Selected") {
                    NotificationCenter.default.post(name: .stopSelectedRequested, object: nil)
                }.keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Start All") {
                    for profile in configManager.config.resolvedProfiles() {
                        let path = configManager.buildPath(for: profile, global: configManager.config.global)
                        processManager.startProfile(profile, path: path)
                    }
                }.keyboardShortcut("a", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Divider()
                ForEach(1..<10, id: \.self) { index in
                    Button("Tab \(index)") {
                        NotificationCenter.default.post(name: .switchToTab, object: nil, userInfo: ["index": index - 1])
                    }.keyboardShortcut(KeyEquivalent(Character(String(index))), modifiers: .command)
                }
            }
        }

        Settings {
            SettingsView(configManager: configManager)
        }

        MenuBarExtra {
            MenuBarView(
                profiles: configManager.config.resolvedProfiles(),
                statusProvider: { processManager.status(for: $0) },
                onStartAll: {
                    for profile in configManager.config.resolvedProfiles() {
                        let path = configManager.buildPath(for: profile, global: configManager.config.global)
                        processManager.startProfile(profile, path: path)
                    }
                },
                onStopAll: { processManager.stopAll() },
                onOpenWindow: { NSApp.activate(ignoringOtherApps: true) },
                onOpenSettings: {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                },
                onQuit: {
                    processManager.stopAll {
                        NSApp.terminate(nil)
                    }
                }
            )
        } label: {
            let hasIssue = configManager.config.resolvedProfiles().contains {
                let s = processManager.status(for: $0.id)
                return s == .crashed || s == .crashLooping
            }
            Image(systemName: hasIssue ? "terminal.fill" : "terminal")
        }
    }
}
