import Foundation

struct AppConfig: Codable, Equatable {
    var openclawPath: String
    var restartDelay: Int

    enum CodingKeys: String, CodingKey {
        case openclawPath = "openclaw_path"
        case restartDelay = "restart_delay"
    }

    init(openclawPath: String = "/opt/homebrew/bin/openclaw", restartDelay: Int = 3) {
        self.openclawPath = openclawPath
        self.restartDelay = restartDelay
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.openclawPath = try c.decodeIfPresent(String.self, forKey: .openclawPath) ?? "/opt/homebrew/bin/openclaw"
        self.restartDelay = try c.decodeIfPresent(Int.self, forKey: .restartDelay) ?? 3
    }

    static func makeDefault() -> AppConfig {
        AppConfig()
    }
}
