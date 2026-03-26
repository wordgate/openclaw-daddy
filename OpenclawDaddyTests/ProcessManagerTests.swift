import XCTest
@testable import OpenclawDaddy

final class ProcessManagerTests: XCTestCase {
    func testStartProfileProcess() throws {
        let profile = Profile(name: "Test", command: "sleep 60", autostart: false)
        let manager = ProcessManager(restartDelay: 1)

        let started = expectation(description: "Process started")
        manager.startProfile(profile, path: "/usr/bin:/bin") { started.fulfill() }
        waitForExpectations(timeout: 5)

        XCTAssertEqual(manager.status(for: profile.id), .running)
        XCTAssertNotNil(manager.masterFd(for: profile.id))

        let stopped = expectation(description: "Process stopped")
        manager.stopProfile(profile.id) { stopped.fulfill() }
        waitForExpectations(timeout: 10)

        XCTAssertEqual(manager.status(for: profile.id), .stopped)
    }

    func testStopProfileProcess() throws {
        let profile = Profile(name: "Sleeper", command: "sleep 60", autostart: false)
        let manager = ProcessManager(restartDelay: 1)

        let started = expectation(description: "Process started")
        manager.startProfile(profile, path: "/usr/bin:/bin") { started.fulfill() }
        waitForExpectations(timeout: 5)

        XCTAssertEqual(manager.status(for: profile.id), .running)

        let stopped = expectation(description: "Process stopped")
        manager.stopProfile(profile.id) { stopped.fulfill() }
        waitForExpectations(timeout: 10)

        XCTAssertEqual(manager.status(for: profile.id), .stopped)
    }

    func testKeepaliveRestartsOnCrash() throws {
        let profile = Profile(name: "Crasher", command: "exit 1", autostart: false)
        let manager = ProcessManager(restartDelay: 1)

        var restartCount = 0
        let restarted = expectation(description: "Process restarted at least once")

        manager.onProcessRestarted = { id in
            if id == profile.id {
                restartCount += 1
                if restartCount >= 1 { restarted.fulfill() }
            }
        }

        manager.startProfile(profile, path: "/usr/bin:/bin")
        waitForExpectations(timeout: 10)

        manager.stopProfile(profile.id)
        XCTAssertGreaterThanOrEqual(restartCount, 1)
    }

    func testNormalExitDoesNotRestart() throws {
        let profile = Profile(name: "CleanExit", command: "exit 0", autostart: false)
        let manager = ProcessManager(restartDelay: 1)

        var restarted = false
        manager.onProcessRestarted = { _ in restarted = true }

        manager.startProfile(profile, path: "/usr/bin:/bin")

        Thread.sleep(forTimeInterval: 3)

        XCTAssertFalse(restarted, "Normal exit (0) should not trigger restart")
        XCTAssertEqual(manager.status(for: profile.id), .stopped)
    }

    func testGetMasterFd() throws {
        let profile = Profile(name: "FdTest", command: "sleep 60", autostart: false)
        let manager = ProcessManager(restartDelay: 1)

        let started = expectation(description: "started")
        manager.startProfile(profile, path: "/usr/bin:/bin") { started.fulfill() }
        waitForExpectations(timeout: 5)

        let fd = manager.masterFd(for: profile.id)
        XCTAssertNotNil(fd)
        XCTAssertTrue(fd! >= 0)

        manager.stopProfile(profile.id)
    }
}
