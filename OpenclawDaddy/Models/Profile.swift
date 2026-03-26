import Foundation

struct Profile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var command: String
    var autostart: Bool
    var path: [String]
    var env: [String: String]
    var logFile: String?

    enum CodingKeys: String, CodingKey {
        case name, command, autostart, path, env
        case logFile = "log_file"
    }

    init(id: UUID = UUID(), name: String, command: String, autostart: Bool = false, path: [String] = [], env: [String: String] = [:], logFile: String? = nil) {
        self.id = id; self.name = name; self.command = command; self.autostart = autostart; self.path = path; self.env = env; self.logFile = logFile
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.name = try c.decode(String.self, forKey: .name)
        self.command = try c.decode(String.self, forKey: .command)
        self.autostart = try c.decodeIfPresent(Bool.self, forKey: .autostart) ?? false
        self.path = try c.decodeIfPresent([String].self, forKey: .path) ?? []
        self.env = try c.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
        self.logFile = try c.decodeIfPresent(String.self, forKey: .logFile)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(command, forKey: .command)
        try c.encode(autostart, forKey: .autostart)
        try c.encode(path, forKey: .path)
        if !env.isEmpty { try c.encode(env, forKey: .env) }
        try c.encodeIfPresent(logFile, forKey: .logFile)
    }
}
