import XCTest
@testable import OpenclawDaddy

final class ProcessManagerTests: XCTestCase {
    func testStartAndStopProfile() throws {
        let manager = ProcessManager(restartDelay: 1)

        guard let (id, fd) = manager.spawnTerminal() else {
            XCTFail("Failed to spawn terminal")
            return
        }

        XCTAssertTrue(fd >= 0)
        XCTAssertTrue(manager.isTerminalRunning(id))

        manager.closeTerminal(id)
        XCTAssertFalse(manager.isTerminalRunning(id))
    }

    func testSpawnTerminal() throws {
        let manager = ProcessManager(restartDelay: 1)
        guard let (id, fd) = manager.spawnTerminal() else {
            XCTFail("Failed to spawn terminal")
            return
        }
        XCTAssertTrue(fd >= 0)
        manager.closeTerminal(id)
    }

    func testUpdateRestartDelay() {
        let manager = ProcessManager(restartDelay: 3)
        manager.updateRestartDelay(10)
        // No public getter, but verify it doesn't crash
    }

    func testStatusForUnknownProfile() {
        let manager = ProcessManager(restartDelay: 1)
        XCTAssertEqual(manager.status(for: "nonexistent"), .stopped)
    }

    func testMasterFdForUnknownProfile() {
        let manager = ProcessManager(restartDelay: 1)
        XCTAssertNil(manager.masterFd(for: "nonexistent"))
    }
}
