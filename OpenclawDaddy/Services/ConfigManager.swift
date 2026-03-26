import Foundation
import Yams

enum ConfigError: LocalizedError {
    case unsupportedVersion(Int)
    case parseError(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let v):
            return "Config version \(v) is not supported. Please update OpenclawDaddy."
        case .parseError(let msg):
            return "Failed to parse config: \(msg)"
        case .saveFailed(let msg):
            return "Failed to save config: \(msg)"
        }
    }
}

@Observable
final class ConfigManager {
    private let configDirectory: URL
    private var configURL: URL { configDirectory.appendingPathComponent("config.yaml") }
    private var fileWatchSource: DispatchSourceFileSystemObject?
    private var debounceWorkItem: DispatchWorkItem?

    private(set) var config: AppConfig = .makeDefault()
    private(set) var validationWarnings: [String] = []

    var onConfigReloaded: ((AppConfig) -> Void)?

    init(configDirectory: URL? = nil) {
        if let dir = configDirectory {
            self.configDirectory = dir
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.configDirectory = home.appendingPathComponent(".openclaw-daddy")
        }
    }

    @discardableResult
    func load() throws -> AppConfig {
        let fm = FileManager.default
        if !fm.fileExists(atPath: configDirectory.path) {
            try fm.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: configURL.path) {
            let defaultConfig = AppConfig.makeDefault()
            try save(defaultConfig)
            self.config = defaultConfig
            return defaultConfig
        }

        let yamlString = try String(contentsOf: configURL, encoding: .utf8)

        if let rawDict = try Yams.load(yaml: yamlString) as? [String: Any],
           let version = rawDict["version"] as? Int,
           version > AppConfig.supportedVersion {
            throw ConfigError.unsupportedVersion(version)
        }

        var warnings: [String] = []
        let config = try decodeLenient(yamlString: yamlString, warnings: &warnings)
        self.validationWarnings = warnings
        self.config = config
        return config
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

    func buildPath(for profile: Profile, global: GlobalConfig) -> String {
        let systemPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        let components = systemPath.split(separator: ":").map(String.init)
            + global.extraPath
            + profile.path
        return components.joined(separator: ":")
    }

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
            guard let self else { return }
            do {
                let newConfig = try self.load()
                self.onConfigReloaded?(newConfig)
            } catch {
                self.validationWarnings.append("Reload failed: \(error.localizedDescription)")
            }
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func decodeLenient(yamlString: String, warnings: inout [String]) throws -> AppConfig {
        guard let rawDict = try Yams.load(yaml: yamlString) as? [String: Any] else {
            throw ConfigError.parseError("Root is not a dictionary")
        }
        let version = rawDict["version"] as? Int ?? 1
        var global = GlobalConfig()
        if let globalDict = rawDict["global"] as? [String: Any] {
            global.restartDelay = globalDict["restart_delay"] as? Int ?? 3
            global.extraPath = globalDict["extra_path"] as? [String] ?? []
        }
        var profiles: [Profile] = []
        if let profilesArray = rawDict["profiles"] as? [[String: Any]] {
            for (index, dict) in profilesArray.enumerated() {
                guard let name = dict["name"] as? String else {
                    warnings.append("Profile at index \(index): missing 'name', skipped")
                    continue
                }
                guard let command = dict["command"] as? String else {
                    warnings.append("Profile '\(name)': missing 'command', skipped")
                    continue
                }
                profiles.append(Profile(
                    name: name, command: command,
                    autostart: dict["autostart"] as? Bool ?? false,
                    path: dict["path"] as? [String] ?? [],
                    env: dict["env"] as? [String: String] ?? [:],
                    logFile: dict["log_file"] as? String
                ))
            }
        }
        return AppConfig(version: version, global: global, profiles: profiles)
    }
}
