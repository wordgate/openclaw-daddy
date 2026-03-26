import SwiftUI
import UserNotifications

extension Notification.Name {
    static let newTerminalRequested = Notification.Name("newTerminalRequested")
    static let restartSelectedRequested = Notification.Name("restartSelectedRequested")
    static let stopSelectedRequested = Notification.Name("stopSelectedRequested")
    static let closeTabRequested = Notification.Name("closeTabRequested")
    static let addProfileRequested = Notification.Name("addProfileRequested")
    static let switchToTab = Notification.Name("switchToTab")
    static let selectProfile = Notification.Name("selectProfile")
}

@main
struct OpenclawDaddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var configManager = ConfigManager()
    @StateObject private var processManager = ProcessManager()
    private let appUpdater = AppUpdater()

    var body: some Scene {
        WindowGroup {
            MainWindow(
                configManager: configManager,
                processManager: processManager,
                onCheckAppUpdate: { appUpdater.checkForUpdates() }
            )
            .onAppear {
                do {
                    let config = try configManager.load()
                    processManager.updateRestartDelay(config.restartDelay)
                    configManager.scanProfiles()
                    configManager.startWatching()
                    // Start all profiles AFTER config is loaded with correct openclawPath
                    for profile in configManager.profiles {
                        processManager.startProfile(profile, openclawPath: configManager.config.openclawPath)
                    }
                } catch {
                    print("Config load error: \(error)")
                }
                appDelegate.processManager = processManager
                processManager.onCrashLoop = { name in
                    let content = UNMutableNotificationContent()
                    content.title = "OpenclawDaddy"
                    content.body = "\(name) is crash-looping"
                    content.sound = .default
                    let request = UNNotificationRequest(identifier: "crash-loop-\(name)", content: content, trigger: nil)
                    UNUserNotificationCenter.current().add(request)
                }
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
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
            CommandGroup(after: .appInfo) {
                Button("Check for App Updates...") {
                    appUpdater.checkForUpdates()
                }
                .disabled(!appUpdater.canCheckForUpdates)
            }
            CommandGroup(after: .toolbar) {
                Button("Restart Selected") {
                    NotificationCenter.default.post(name: .restartSelectedRequested, object: nil)
                }.keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Stop Selected") {
                    NotificationCenter.default.post(name: .stopSelectedRequested, object: nil)
                }.keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Start All") {
                    for profile in configManager.profiles {
                        processManager.startProfile(profile, openclawPath: configManager.config.openclawPath)
                    }
                }.keyboardShortcut("a", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra("OpenclawDaddy", image: "MenuBarIcon") {
            MenuBarView(
                profiles: configManager.profiles,
                statusProvider: { processManager.status(for: $0) },
                onStartProfile: { profile in
                    processManager.startProfile(profile, openclawPath: configManager.config.openclawPath)
                },
                onStopProfile: { processManager.stopProfile($0) },
                onStartAll: {
                    for profile in configManager.profiles {
                        processManager.startProfile(profile, openclawPath: configManager.config.openclawPath)
                    }
                },
                onStopAll: { processManager.stopAll() },
                onOpenWindow: { NSApp.activate(ignoringOtherApps: true) },
                onQuit: {
                    processManager.stopAll { NSApp.terminate(nil) }
                }
            )
        }
    }
}
