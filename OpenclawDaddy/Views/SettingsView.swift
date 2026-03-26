import SwiftUI

struct SettingsView: View {
    @State var configManager: ConfigManager
    @State private var editableConfig: AppConfig = .makeDefault()
    @State private var saveError: String?

    var body: some View {
        TabView {
            profilesTab.tabItem { Label("Profiles", systemImage: "list.bullet") }
            PermissionsView().tabItem { Label("Permissions", systemImage: "lock.shield") }
            globalTab.tabItem { Label("Global", systemImage: "gearshape") }
        }
        .frame(width: 600, height: 450)
        .onAppear { editableConfig = configManager.config }
    }

    private var profilesTab: some View {
        VStack {
            if editableConfig.profiles.isEmpty {
                Text("No profiles. Click + to add one.").foregroundStyle(.secondary).frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(editableConfig.profiles.enumerated()), id: \.element.id) { index, _ in
                        ProfileEditorView(
                            profile: $editableConfig.profiles[index],
                            onDelete: { editableConfig.profiles.remove(at: index); saveConfig() }
                        )
                    }
                }
            }
            HStack {
                Button {
                    editableConfig.profiles.append(Profile(name: "New Profile", command: "openclaw --profile new run"))
                    saveConfig()
                } label: { Label("Add Profile", systemImage: "plus") }
                Spacer()
                if let error = saveError { Text(error).foregroundStyle(.red).font(.caption) }
                Button("Save") { saveConfig() }.keyboardShortcut("s")
            }.padding()
        }
    }

    private var globalTab: some View {
        Form {
            Section("Restart") {
                Stepper("Restart delay: \(editableConfig.global.restartDelay)s",
                       value: $editableConfig.global.restartDelay, in: 1...60)
            }
            Section("Extra PATH (global)") {
                ForEach(Array(editableConfig.global.extraPath.enumerated()), id: \.offset) { index, path in
                    HStack {
                        Text(path).font(.system(.body, design: .monospaced))
                        Spacer()
                        Button(role: .destructive) { editableConfig.global.extraPath.remove(at: index) } label: {
                            Image(systemName: "minus.circle")
                        }.buttonStyle(.plain)
                    }
                }
            }
            Section { Button("Save") { saveConfig() }.keyboardShortcut("s") }
        }.formStyle(.grouped)
    }

    private func saveConfig() {
        do { try configManager.save(editableConfig); saveError = nil }
        catch { saveError = error.localizedDescription }
    }
}
