import XCTest
@testable import OpenclawDaddy

final class AppConfigTests: XCTestCase {
    func testDefaultConfig() {
        let config = AppConfig.makeDefault()
        XCTAssertEqual(config.openclawPath, "/opt/homebrew/bin/openclaw")
        XCTAssertEqual(config.restartDelay, 3)
    }

    func testCustomConfig() {
        let config = AppConfig(openclawPath: "/usr/local/bin/openclaw", restartDelay: 5)
        XCTAssertEqual(config.openclawPath, "/usr/local/bin/openclaw")
        XCTAssertEqual(config.restartDelay, 5)
    }

    func testProfileCommand() {
        let profile = Profile(name: "gateway")
        XCTAssertEqual(profile.command(openclawPath: "/usr/bin/openclaw"), "/usr/bin/openclaw --profile gateway gateway")
    }

    func testProfileId() {
        let profile = Profile(name: "worker")
        XCTAssertEqual(profile.id, "worker")
    }

    func testProfileStateDirectory() {
        let profile = Profile(name: "test")
        let home = FileManager.default.homeDirectoryForCurrentUser
        XCTAssertEqual(profile.stateDirectory, home.appendingPathComponent(".openclaw-test"))
    }
}
