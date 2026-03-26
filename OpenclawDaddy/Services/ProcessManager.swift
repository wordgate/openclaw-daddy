import Foundation

// Swift replacements for C wait macros
private func wIfExited(_ status: Int32) -> Bool {
    return (status & 0x7F) == 0
}

private func wExitStatus(_ status: Int32) -> Int32 {
    return (status >> 8) & 0xFF
}

private func wIfSignaled(_ status: Int32) -> Bool {
    let s = status & 0x7F
    return s != 0x7F && s != 0
}

enum ProcessStatus: String {
    case running, stopped, crashed, crashLooping
}

final class ProcessManager: ObservableObject {
    struct ManagedProcess {
        let name: String
        var pty: PTYProcess
        var status: ProcessStatus
        var processSource: DispatchSourceProcess?
        var consecutiveQuickCrashes: Int = 0
        var lastStartTime: Date = Date()
        var isStoppedByUser: Bool = false
    }

    // All access on main thread only
    private var processes: [String: ManagedProcess] = [:]
    private var restartDelay: Int
    private let queue = DispatchQueue(label: "com.wordgate.openclaw-daddy.process-manager")
    private let logManager = LogManager()

    @Published private(set) var stateVersion: Int = 0

    var onCrashLoop: ((String) -> Void)?

    init(restartDelay: Int = 3) {
        self.restartDelay = restartDelay
    }

    func updateRestartDelay(_ delay: Int) {
        restartDelay = delay
    }

    private func notifyStateChange() {
        stateVersion += 1
    }

    func status(for name: String) -> ProcessStatus {
        _ = stateVersion
        return processes[name]?.status ?? .stopped
    }

    func masterFd(for name: String) -> Int32? {
        _ = stateVersion
        return processes[name]?.pty.masterFd
    }

    // MARK: - Profile Process Management

    func startProfile(_ profile: Profile, openclawPath: String) {
        let name = profile.name
        let command = profile.command(openclawPath: openclawPath)

        queue.async { [weak self] in
            guard let self else { return }
            do {
                let env = ProcessInfo.processInfo.environment
                let pty = try PTYManager.spawnShell(
                    shellCommand: command,
                    environment: env,
                    workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path
                )

                var managed = ManagedProcess(
                    name: name,
                    pty: pty,
                    status: .running,
                    lastStartTime: Date()
                )

                let source = DispatchSource.makeProcessSource(
                    identifier: pty.pid,
                    eventMask: .exit,
                    queue: self.queue
                )
                source.setEventHandler { [weak self] in
                    self?.handleProcessExit(name: name, openclawPath: openclawPath)
                }
                source.resume()
                managed.processSource = source

                DispatchQueue.main.async {
                    self.processes[name] = managed
                    self.notifyStateChange()
                }
            } catch {
                DispatchQueue.main.async {
                    self.processes[name] = ManagedProcess(
                        name: name,
                        pty: PTYProcess(pid: -1, masterFd: -1),
                        status: .crashed
                    )
                    self.notifyStateChange()
                }
            }
        }
    }

    func stopProfile(_ name: String, onStopped: (() -> Void)? = nil) {
        guard let managed = processes[name] else {
            onStopped?()
            return
        }

        processes[name]?.isStoppedByUser = true
        processes[name]?.processSource?.cancel()
        processes[name]?.processSource = nil
        notifyStateChange()

        let pid = managed.pty.pid
        guard pid > 0 else {
            processes[name]?.status = .stopped
            notifyStateChange()
            onStopped?()
            return
        }

        kill(pid, SIGTERM)

        queue.asyncAfter(deadline: .now() + 5) { [weak self] in
            var status: Int32 = 0
            let result = waitpid(pid, &status, WNOHANG)
            if result == 0 {
                kill(pid, SIGKILL)
                waitpid(pid, &status, WNOHANG)
            }
            managed.pty.cleanup()
            DispatchQueue.main.async {
                self?.processes[name]?.status = .stopped
                self?.notifyStateChange()
                onStopped?()
            }
        }
    }

    func restartProfile(_ profile: Profile, openclawPath: String) {
        stopProfile(profile.name) { [weak self] in
            self?.startProfile(profile, openclawPath: openclawPath)
        }
    }

    func stopAll(onComplete: (() -> Void)? = nil) {
        let group = DispatchGroup()
        for name in Array(processes.keys) {
            group.enter()
            stopProfile(name) { group.leave() }
        }
        group.notify(queue: .main) { [weak self] in
            self?.logManager.stopAll()
            onComplete?()
        }
    }

    // MARK: - Terminal Tabs

    func spawnTerminal() -> (UUID, Int32)? {
        do {
            let pty = try PTYManager.spawnInteractiveShell()
            let id = UUID()
            let managed = ManagedProcess(name: "terminal-\(id)", pty: pty, status: .running)
            processes["terminal-\(id)"] = managed
            return (id, pty.masterFd)
        } catch {
            return nil
        }
    }

    func closeTerminal(_ id: UUID) {
        let key = "terminal-\(id)"
        guard let managed = processes[key] else { return }
        if managed.pty.pid > 0 { kill(managed.pty.pid, SIGTERM) }
        managed.pty.cleanup()
        processes.removeValue(forKey: key)
    }

    func isTerminalRunning(_ id: UUID) -> Bool {
        let key = "terminal-\(id)"
        guard let managed = processes[key], managed.pty.pid > 0 else { return false }
        var status: Int32 = 0
        let result = waitpid(managed.pty.pid, &status, WNOHANG)
        return result == 0
    }

    // MARK: - Private

    private func handleProcessExit(name: String, openclawPath: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let managed = self.processes[name] else { return }
            if managed.isStoppedByUser { return }

            var waitStatus: Int32 = 0
            waitpid(managed.pty.pid, &waitStatus, WNOHANG)

            let exitCode = wIfExited(waitStatus) ? Int(wExitStatus(waitStatus)) : -1
            let wasSignaled = wIfSignaled(waitStatus)

            if exitCode == 0 && !wasSignaled {
                self.processes[name]?.status = .stopped
                self.notifyStateChange()
                // Even normal exit → restart, because the purpose is keepalive
            }

            let elapsed = Date().timeIntervalSince(managed.lastStartTime)
            let crashes = elapsed < 1.0 ? managed.consecutiveQuickCrashes + 1 : 0
            let isCrashLooping = crashes >= 10

            self.processes[name]?.status = isCrashLooping ? .crashLooping : .crashed
            self.processes[name]?.consecutiveQuickCrashes = crashes
            self.notifyStateChange()

            if isCrashLooping {
                self.onCrashLoop?(name)
                return
            }

            // Restart after delay
            let delay = self.restartDelay
            self.queue.asyncAfter(deadline: .now() + .seconds(delay)) { [weak self] in
                guard let self else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard let current = self.processes[name], !current.isStoppedByUser else { return }
                    current.pty.cleanup()
                    current.processSource?.cancel()

                    let profile = Profile(name: name)
                    self.queue.async { [weak self] in
                        do {
                            let env = ProcessInfo.processInfo.environment
                            let newPty = try PTYManager.spawnShell(
                                shellCommand: profile.command(openclawPath: openclawPath),
                                environment: env
                            )
                            let source = DispatchSource.makeProcessSource(
                                identifier: newPty.pid,
                                eventMask: .exit,
                                queue: self?.queue ?? .global()
                            )
                            source.setEventHandler { [weak self] in
                                self?.handleProcessExit(name: name, openclawPath: openclawPath)
                            }
                            source.resume()

                            DispatchQueue.main.async { [weak self] in
                                self?.processes[name]?.pty = newPty
                                self?.processes[name]?.status = .running
                                self?.processes[name]?.processSource = source
                                self?.processes[name]?.lastStartTime = Date()
                                self?.notifyStateChange()
                            }
                        } catch {
                            DispatchQueue.main.async { [weak self] in
                                self?.processes[name]?.status = .crashed
                                self?.notifyStateChange()
                            }
                        }
                    }
                }
            }
        }
    }
}
