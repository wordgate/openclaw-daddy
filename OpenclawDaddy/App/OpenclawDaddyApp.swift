import SwiftUI

@main
struct OpenclawDaddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            Text("OpenclawDaddy — Loading...")
                .frame(minWidth: 800, minHeight: 500)
        }
        .defaultSize(width: 1000, height: 600)
    }
}
