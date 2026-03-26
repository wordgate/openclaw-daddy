import Foundation

/// A profile is just a name, corresponding to ~/.openclaw-<name>/
struct Profile: Identifiable, Equatable, Hashable {
    var id: String { name }
    let name: String

    /// The command to launch this profile
    func command(openclawPath: String) -> String {
        "\(openclawPath) --profile \(name) gateway"
    }

    /// The state directory for this profile
    var stateDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw-\(name)")
    }
}
