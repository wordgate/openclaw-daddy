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
            }
        }
        .defaultSize(width: 1000, height: 600)
        .windowResizability(.contentSize)

        Settings {
            Text("Settings placeholder")
        }
    }
}
