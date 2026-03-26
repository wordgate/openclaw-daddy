import SwiftUI

struct ProfileEditorView: View {
    @Binding var profile: Profile
    let onDelete: () -> Void
    @State private var newPathEntry = ""
    @State private var newEnvKey = ""
    @State private var newEnvValue = ""

    var body: some View {
        Form {
            Section("Basic") {
                TextField("Name", text: $profile.name)
                TextField("Command", text: $profile.command).font(.system(.body, design: .monospaced))
                Toggle("Autostart", isOn: $profile.autostart)
            }
            Section("PATH Entries") {
                ForEach(Array(profile.path.enumerated()), id: \.offset) { index, path in
                    HStack {
                        Text(path).font(.system(.body, design: .monospaced))
                        Spacer()
                        Button(role: .destructive) { profile.path.remove(at: index) } label: {
                            Image(systemName: "minus.circle")
                        }.buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("Add path...", text: $newPathEntry).font(.system(.body, design: .monospaced))
                    Button {
                        if !newPathEntry.isEmpty { profile.path.append(newPathEntry); newPathEntry = "" }
                    } label: { Image(systemName: "plus.circle") }
                }
            }
            Section("Environment Variables") {
                ForEach(Array(profile.env.keys.sorted()), id: \.self) { key in
                    HStack {
                        Text("\(key)=\(profile.env[key] ?? "")").font(.system(.body, design: .monospaced))
                        Spacer()
                        Button(role: .destructive) { profile.env.removeValue(forKey: key) } label: {
                            Image(systemName: "minus.circle")
                        }.buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("KEY", text: $newEnvKey).font(.system(.body, design: .monospaced)).frame(width: 120)
                    Text("=")
                    TextField("VALUE", text: $newEnvValue).font(.system(.body, design: .monospaced))
                    Button {
                        if !newEnvKey.isEmpty { profile.env[newEnvKey] = newEnvValue; newEnvKey = ""; newEnvValue = "" }
                    } label: { Image(systemName: "plus.circle") }
                }
            }
            Section("Log") {
                TextField("Log file path (optional)", text: Binding(
                    get: { profile.logFile ?? "" },
                    set: { profile.logFile = $0.isEmpty ? nil : $0 }
                )).font(.system(.body, design: .monospaced))
            }
            Section {
                Button("Delete Profile", role: .destructive) { onDelete() }
            }
        }.formStyle(.grouped)
    }
}
