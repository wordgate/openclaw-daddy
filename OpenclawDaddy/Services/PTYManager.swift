import Foundation

struct PTYProcess {
    let pid: pid_t
    let masterFd: Int32

    func cleanup() {
        close(masterFd)
    }
}

enum PTYError: LocalizedError {
    case forkptyFailed
    case execFailed(String)

    var errorDescription: String? {
        switch self {
        case .forkptyFailed:
            return "forkpty() failed: \(String(cString: strerror(errno)))"
        case .execFailed(let cmd):
            return "Failed to exec: \(cmd)"
        }
    }
}

enum PTYManager {
    static func spawn(
        command: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: String = "/",
        initialCols: UInt16 = 80,
        initialRows: UInt16 = 24
    ) throws -> PTYProcess {
        var masterFd: Int32 = -1
        var winSize = winsize(ws_row: initialRows, ws_col: initialCols, ws_xpixel: 0, ws_ypixel: 0)

        let pid = forkpty(&masterFd, nil, nil, &winSize)

        if pid < 0 { throw PTYError.forkptyFailed }

        if pid == 0 {
            chdir(workingDirectory)
            for (key, value) in environment { setenv(key, value, 1) }
            setenv("TERM", "xterm-256color", 1)

            let argv = [command] + arguments
            let cArgs = argv.map { strdup($0) } + [nil]
            defer { cArgs.forEach { free($0) } }

            execvp(command, cArgs)
            _exit(127)
        }

        return PTYProcess(pid: pid, masterFd: masterFd)
    }

    static func spawnShell(
        shellCommand: String,
        environment: [String: String],
        workingDirectory: String = "/"
    ) throws -> PTYProcess {
        try spawn(command: "/bin/bash", arguments: ["-l", "-c", shellCommand],
                  environment: environment, workingDirectory: workingDirectory)
    }

    static func spawnInteractiveShell(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> PTYProcess {
        let shell = environment["SHELL"] ?? "/bin/zsh"
        return try spawn(command: shell, arguments: ["-l"], environment: environment,
                        workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path)
    }

    static func resize(masterFd: Int32, cols: UInt16, rows: UInt16) {
        var size = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        ioctl(masterFd, TIOCSWINSZ, &size)
    }
}
