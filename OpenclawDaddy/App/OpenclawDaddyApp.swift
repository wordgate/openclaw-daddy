import SwiftUI

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
            }
        }
        .defaultSize(width: 1000, height: 600)
        .windowResizability(.contentSize)

        Settings {
            Text("Settings placeholder")
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
