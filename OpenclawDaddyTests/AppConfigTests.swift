import XCTest
import Yams
@testable import OpenclawDaddy

final class AppConfigTests: XCTestCase {
    func testProfileDecodingFromYAML() throws {
        let yaml = """
        name: "Gateway"
        command: "openclaw --profile gateway run"
        autostart: true
        path:
          - /usr/local/bin
        env:
          OPENCLAW_PORT: "8080"
        """
        let profile = try YAMLDecoder().decode(Profile.self, from: yaml)
        XCTAssertEqual(profile.name, "Gateway")
        XCTAssertEqual(profile.command, "openclaw --profile gateway run")
        XCTAssertTrue(profile.autostart)
        XCTAssertEqual(profile.path, ["/usr/local/bin"])
        XCTAssertEqual(profile.env, ["OPENCLAW_PORT": "8080"])
        XCTAssertNil(profile.logFile)
    }

    func testProfileDecodingMinimalFields() throws {
        let yaml = """
        name: "Worker"
        command: "openclaw --profile worker run"
        """
        let profile = try YAMLDecoder().decode(Profile.self, from: yaml)
        XCTAssertEqual(profile.name, "Worker")
        XCTAssertFalse(profile.autostart)
        XCTAssertEqual(profile.path, [])
        XCTAssertEqual(profile.env, [:])
    }

    func testProfileEncodingRoundTrip() throws {
        let profile = Profile(name: "Test", command: "echo hello", autostart: true, path: ["/opt/bin"], env: ["KEY": "VAL"], logFile: "~/.openclaw-daddy/logs/test.log")
        let yaml = try YAMLEncoder().encode(profile)
        let decoded = try YAMLDecoder().decode(Profile.self, from: yaml)
        XCTAssertEqual(profile.name, decoded.name)
        XCTAssertEqual(profile.command, decoded.command)
        XCTAssertEqual(profile.autostart, decoded.autostart)
        XCTAssertEqual(profile.path, decoded.path)
        XCTAssertEqual(profile.env, decoded.env)
        XCTAssertEqual(profile.logFile, decoded.logFile)
    }

    func testAppConfigDecodingFullYAML() throws {
        let yaml = """
        version: 1
        global:
          restart_delay: 3
          extra_path:
            - /usr/local/bin
            - /opt/homebrew/bin
        profiles:
          - name: "Gateway"
            command: "openclaw --profile gateway run"
            autostart: true
        """
        let config = try YAMLDecoder().decode(AppConfig.self, from: yaml)
        XCTAssertEqual(config.version, 1)
        XCTAssertEqual(config.global.restartDelay, 3)
        XCTAssertEqual(config.global.extraPath, ["/usr/local/bin", "/opt/homebrew/bin"])
        XCTAssertEqual(config.profiles.count, 1)
        XCTAssertEqual(config.profiles[0].name, "Gateway")
    }

    func testAppConfigDefaultVersion() throws {
        let yaml = """
        global:
          restart_delay: 5
        profiles: []
        """
        let config = try YAMLDecoder().decode(AppConfig.self, from: yaml)
        XCTAssertEqual(config.version, 1)
    }

    func testAppConfigDefaultConfig() {
        let config = AppConfig.makeDefault()
        XCTAssertEqual(config.version, 1)
        XCTAssertEqual(config.global.restartDelay, 3)
        XCTAssertTrue(config.global.extraPath.contains("/usr/local/bin"))
        XCTAssertTrue(config.global.extraPath.contains("/opt/homebrew/bin"))
        XCTAssertTrue(config.profiles.isEmpty)
    }

    func testAppConfigEncodingRoundTrip() throws {
        let config = AppConfig.makeDefault()
        let yaml = try YAMLEncoder().encode(config)
        let decoded = try YAMLDecoder().decode(AppConfig.self, from: yaml)
        XCTAssertEqual(config.version, decoded.version)
        XCTAssertEqual(config.global.restartDelay, decoded.global.restartDelay)
    }

    func testGlobalConfigEncodesToSnakeCase() throws {
        let global = GlobalConfig(restartDelay: 5, extraPath: ["/test"])
        let yaml = try YAMLEncoder().encode(global)
        XCTAssertTrue(yaml.contains("restart_delay"), "Should encode as snake_case, got: \(yaml)")
        XCTAssertTrue(yaml.contains("extra_path"), "Should encode as snake_case, got: \(yaml)")
        XCTAssertFalse(yaml.contains("restartDelay"), "Should NOT use camelCase")
    }

    func testDuplicateProfileNamesGetSuffix() {
        var config = AppConfig.makeDefault()
        config.profiles = [
            Profile(name: "Gateway", command: "cmd1"),
            Profile(name: "Gateway", command: "cmd2"),
            Profile(name: "Gateway", command: "cmd3"),
        ]
        let resolved = config.resolvedProfiles()
        XCTAssertEqual(resolved[0].name, "Gateway")
        XCTAssertEqual(resolved[1].name, "Gateway (2)")
        XCTAssertEqual(resolved[2].name, "Gateway (3)")
    }
}
