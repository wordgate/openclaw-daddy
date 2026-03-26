import XCTest
@testable import OpenclawDaddy

final class PTYManagerTests: XCTestCase {
    func testSpawnProcessAndReadOutput() throws {
        let expectation = expectation(description: "Read output from spawned process")
        let pty = try PTYManager.spawn(
            command: "/bin/echo", arguments: ["hello-pty-test"],
            environment: ["PATH": "/usr/bin:/bin"], workingDirectory: "/tmp"
        )
        XCTAssertTrue(pty.pid > 0, "PID should be positive")
        XCTAssertTrue(pty.masterFd >= 0, "Master fd should be valid")

        DispatchQueue.global().async {
            var buffer = [UInt8](repeating: 0, count: 1024)
            let bytesRead = read(pty.masterFd, &buffer, buffer.count)
            if bytesRead > 0 {
                let output = String(bytes: buffer[0..<bytesRead], encoding: .utf8) ?? ""
                if output.contains("hello-pty-test") { expectation.fulfill() }
            }
        }
        waitForExpectations(timeout: 5)
        pty.cleanup()
    }

    func testSpawnProcessWriteInput() throws {
        let pty = try PTYManager.spawn(
            command: "/bin/cat", arguments: [],
            environment: ["PATH": "/usr/bin:/bin"], workingDirectory: "/tmp"
        )
        let testString = "input-test\n"
        testString.withCString { ptr in write(pty.masterFd, ptr, strlen(ptr)) }

        let expectation = expectation(description: "Read echoed input")
        DispatchQueue.global().async {
            var buffer = [UInt8](repeating: 0, count: 1024)
            var accumulated = ""
            for _ in 0..<10 {
                let bytesRead = read(pty.masterFd, &buffer, buffer.count)
                if bytesRead > 0 {
                    accumulated += String(bytes: buffer[0..<bytesRead], encoding: .utf8) ?? ""
                    if accumulated.contains("input-test") { expectation.fulfill(); return }
                }
            }
        }
        waitForExpectations(timeout: 5)
        kill(pty.pid, SIGTERM)
        pty.cleanup()
    }

    func testResizeTerminal() throws {
        let pty = try PTYManager.spawn(
            command: "/bin/cat", arguments: [],
            environment: ["PATH": "/usr/bin:/bin"], workingDirectory: "/tmp"
        )
        PTYManager.resize(masterFd: pty.masterFd, cols: 120, rows: 40)
        var size = winsize()
        ioctl(pty.masterFd, TIOCGWINSZ, &size)
        XCTAssertEqual(size.ws_col, 120)
        XCTAssertEqual(size.ws_row, 40)
        kill(pty.pid, SIGTERM)
        pty.cleanup()
    }
}
