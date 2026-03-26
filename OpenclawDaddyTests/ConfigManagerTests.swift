import XCTest
@testable import OpenclawDaddy

final class ConfigManagerTests: XCTestCase {
    var tempDir: URL!
    var configPath: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("openclaw-daddy-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        configPath = tempDir.appendingPathComponent("config.yaml")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testLoadCreatesDefaultWhenFileMissing() throws {
        let manager = ConfigManager(configDirectory: tempDir)
        let config = try manager.load()
        XCTAssertEqual(config.version, 1)
        XCTAssertEqual(config.global.restartDelay, 3)
        XCTAssertTrue(config.profiles.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: configPath.path))
    }

    func testLoadParsesExistingConfig() throws {
        let yaml = """
        version: 1
        global:
          restart_delay: 5
          extra_path:
            - /custom/bin
        profiles:
          - name: "Test"
            command: "echo hello"
            autostart: true
        """
        try yaml.write(to: configPath, atomically: true, encoding: .utf8)
        let manager = ConfigManager(configDirectory: tempDir)
        let config = try manager.load()
        XCTAssertEqual(config.global.restartDelay, 5)
        XCTAssertEqual(config.profiles.count, 1)
        XCTAssertEqual(config.profiles[0].name, "Test")
    }

    func testLoadRejectsUnsupportedVersion() throws {
        let yaml = """
        version: 99
        global:
          restart_delay: 3
        profiles: []
        """
        try yaml.write(to: configPath, atomically: true, encoding: .utf8)
        let manager = ConfigManager(configDirectory: tempDir)
        XCTAssertThrowsError(try manager.load()) { error in
            let message = (error as? ConfigError).flatMap { $0.errorDescription } ?? "\(error)"
            XCTAssertTrue(message.contains("update"), "Error should mention updating the app, got: \(message)")
        }
    }

    func testSaveWritesValidYAML() throws {
        let manager = ConfigManager(configDirectory: tempDir)
        var config = AppConfig.makeDefault()
        config.profiles = [Profile(name: "Saved", command: "echo saved", autostart: true)]
        try manager.save(config)
        let loaded = try manager.load()
        XCTAssertEqual(loaded.profiles.count, 1)
        XCTAssertEqual(loaded.profiles[0].name, "Saved")
    }

    func testLoadSkipsProfilesMissingRequiredFields() throws {
        let yaml = """
        version: 1
        global:
          restart_delay: 3
        profiles:
          - name: "Valid"
            command: "echo valid"
          - name: "Invalid"
        """
        try yaml.write(to: configPath, atomically: true, encoding: .utf8)
        let manager = ConfigManager(configDirectory: tempDir)
        let config = try manager.load()
        XCTAssertEqual(config.profiles.count, 1)
        XCTAssertEqual(config.profiles[0].name, "Valid")
    }

    func testBuildPathForProfile() {
        let config = AppConfig(
            global: GlobalConfig(extraPath: ["/global/bin"]),
            profiles: [Profile(name: "T", command: "cmd", path: ["/profile/bin"])]
        )
        let manager = ConfigManager(configDirectory: tempDir)
        let path = manager.buildPath(for: config.profiles[0], global: config.global)
        XCTAssertTrue(path.contains("/global/bin"))
        XCTAssertTrue(path.contains("/profile/bin"))
        XCTAssertTrue(path.contains("/usr/bin"))
    }
}
