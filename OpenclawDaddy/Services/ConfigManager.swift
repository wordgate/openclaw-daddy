import Foundation
import Yams

enum ConfigError: LocalizedError {
    case parseError(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .parseError(let msg): return "Failed to parse config: \(msg)"
        case .saveFailed(let msg): return "Failed to save config: \(msg)"
        }
    }
}

final class ConfigManager: ObservableObject {
    private let configDirectory: URL
    private var configURL: URL { configDirectory.appendingPathComponent("config.yaml") }
    private var fileWatchSource: DispatchSourceFileSystemObject?
    private var debounceWorkItem: DispatchWorkItem?

    @Published var config: AppConfig = .makeDefault()
    @Published var profiles: [Profile] = []

    init(configDirectory: URL? = nil) {
        if let dir = configDirectory {
            self.configDirectory = dir
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.configDirectory = home.appendingPathComponent(".openclaw-daddy")
        }
    }

    // MARK: - Config File

    @discardableResult
    func load() throws -> AppConfig {
        let fm = FileManager.default
        if !fm.fileExists(atPath: configDirectory.path) {
            try fm.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: configURL.path) {
            let defaultConfig = AppConfig.makeDefault()
            // Auto-detect openclaw before saving default
            if let detected = detectOpenclawPath() {
                var cfg = defaultConfig
                cfg.openclawPath = detected
                try save(cfg)
                return cfg
            }
            try save(defaultConfig)
            return defaultConfig
        }

        let yamlString = try String(contentsOf: configURL, encoding: .utf8)
        let decoded = try YAMLDecoder().decode(AppConfig.self, from: yamlString)
        self.config = decoded
        return decoded
    }

    func save(_ config: AppConfig) throws {
        let encoder = YAMLEncoder()
        let yamlString = try encoder.encode(config)
        do {
            try yamlString.write(to: configURL, atomically: true, encoding: .utf8)
            self.config = config
        } catch {
            throw ConfigError.saveFailed(error.localizedDescription)
        }
    }

    // MARK: - Profile Discovery

    /// Scan ~/.openclaw-* directories to discover profiles
    func scanProfiles() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: home.path) else {
            profiles = []
            return
        }
        profiles = contents
            .filter { $0.hasPrefix(".openclaw-") && $0 != ".openclaw-daddy" && $0 != ".openclaw-dev" }
            .map { String($0.dropFirst(".openclaw-".count)) }
            .sorted()
            .map { Profile(name: $0) }
    }

    /// Create a new profile via `openclaw --profile <name> setup --non-interactive`
    func createProfile(name: String, in pty: PTYProcess? = nil) throws -> PTYProcess {
        let env = ProcessInfo.processInfo.environment
        return try PTYManager.spawnShell(
            shellCommand: "\(config.openclawPath) --profile \(name) setup --non-interactive",
            environment: env
        )
    }

    // MARK: - openclaw Detection

    func detectOpenclawPath() -> String? {
        let knownPaths = [
            "/opt/homebrew/bin/openclaw",
            "/usr/local/bin/openclaw",
            "/usr/bin/openclaw"
        ]

        for path in knownPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Try `which openclaw`
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["openclaw"]
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()

        if proc.terminationStatus == 0,
           let data = try? pipe.fileHandleForReading.readDataToEndOfFile(),
           let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            return path
        }

        // Try common nvm/node paths
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let nodePaths = [
            "\(home)/.nvm/versions/node",
            "\(home)/.volta/bin"
        ]
        for base in nodePaths {
            if let versions = try? FileManager.default.contentsOfDirectory(atPath: base) {
                for version in versions.sorted().reversed() {
                    let candidate = "\(base)/\(version)/bin/openclaw"
                    if FileManager.default.isExecutableFile(atPath: candidate) {
                        return candidate
                    }
                }
            }
        }

        return nil
    }

    /// Check if the configured openclaw path is valid
    var isOpenclawValid: Bool {
        FileManager.default.isExecutableFile(atPath: config.openclawPath)
    }

    // MARK: - File Watching

    func startWatching() {
        let fd = open(configURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main
        )
        source.setEventHandler { [weak self] in self?.handleFileChange() }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.fileWatchSource = source
    }

    func stopWatching() {
        fileWatchSource?.cancel()
        fileWatchSource = nil
    }

    private func handleFileChange() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            try? self?.load()
            self?.scanProfiles()
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}
