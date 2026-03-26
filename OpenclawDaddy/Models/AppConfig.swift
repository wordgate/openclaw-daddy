import Foundation

struct GlobalConfig: Codable, Equatable {
    var restartDelay: Int
    var extraPath: [String]

    enum CodingKeys: String, CodingKey {
        case restartDelay = "restart_delay"
        case extraPath = "extra_path"
    }

    init(restartDelay: Int = 3, extraPath: [String] = []) {
        self.restartDelay = restartDelay; self.extraPath = extraPath
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.restartDelay = try c.decodeIfPresent(Int.self, forKey: .restartDelay) ?? 3
        self.extraPath = try c.decodeIfPresent([String].self, forKey: .extraPath) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(restartDelay, forKey: .restartDelay)
        try c.encode(extraPath, forKey: .extraPath)
    }
}

struct AppConfig: Codable, Equatable {
    var version: Int
    var global: GlobalConfig
    var profiles: [Profile]

    static let supportedVersion = 1

    init(version: Int = 1, global: GlobalConfig = GlobalConfig(), profiles: [Profile] = []) {
        self.version = version; self.global = global; self.profiles = profiles
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        self.global = try c.decodeIfPresent(GlobalConfig.self, forKey: .global) ?? GlobalConfig()
        self.profiles = try c.decodeIfPresent([Profile].self, forKey: .profiles) ?? []
    }

    static func makeDefault() -> AppConfig {
        AppConfig(version: 1, global: GlobalConfig(restartDelay: 3, extraPath: ["/usr/local/bin", "/opt/homebrew/bin"]), profiles: [])
    }

    func resolvedProfiles() -> [Profile] {
        var nameCounts: [String: Int] = [:]
        return profiles.map { profile in
            var resolved = profile
            let count = nameCounts[profile.name, default: 0]
            nameCounts[profile.name] = count + 1
            if count > 0 { resolved.name = "\(profile.name) (\(count + 1))" }
            return resolved
        }
    }
}
