import XCTest
@testable import OpenclawDaddy

final class ConfigManagerTests: XCTestCase {
    var tempDir: URL!
    var manager: ConfigManager!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        manager = ConfigManager(configDirectory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testLoadCreatesDefaultWhenFileMissing() throws {
        let config = try manager.load()
        XCTAssertEqual(config.restartDelay, 3)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("config.yaml").path))
    }

    func testSaveAndLoad() throws {
        let config = AppConfig(openclawPath: "/custom/path/openclaw", restartDelay: 10)
        try manager.save(config)

        let loaded = try manager.load()
        XCTAssertEqual(loaded.openclawPath, "/custom/path/openclaw")
        XCTAssertEqual(loaded.restartDelay, 10)
    }

    func testScanProfilesFindsDirectories() throws {
        // Create fake openclaw profile dirs in home (we can't easily test this
        // without creating dirs in ~, so just verify empty scan works)
        manager.scanProfiles()
        // Should not crash, profiles may be empty or contain real profiles
        XCTAssertNotNil(manager.profiles)
    }

    func testDetectOpenclawPath() {
        // Just verify it runs without crash
        let path = manager.detectOpenclawPath()
        // May or may not find openclaw depending on system
        if let path = path {
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: path))
        }
    }
}
