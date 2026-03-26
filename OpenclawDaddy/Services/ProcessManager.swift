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

@Observable
final class ProcessManager {
    struct ManagedProcess {
        let profileId: UUID
        var pty: PTYProcess
        var status: ProcessStatus
        var processSource: DispatchSourceProcess?
        var consecutiveQuickCrashes: Int = 0
        var lastStartTime: Date = Date()
        var isStoppedByUser: Bool = false
    }

    private var processes: [UUID: ManagedProcess] = [:]
    private let restartDelay: Int
    private let queue = DispatchQueue(label: "com.wordgate.openclaw-daddy.process-manager")

    private(set) var stateVersion: Int = 0

    var onProcessRestarted: ((UUID) -> Void)?
    var onCrashLoop: ((UUID, String) -> Void)?

    init(restartDelay: Int = 3) {
        self.restartDelay = restartDelay
    }

    private func notifyStateChange() {
        stateVersion += 1
    }

    func status(for profileId: UUID) -> ProcessStatus {
        _ = stateVersion
        return processes[profileId]?.status ?? .stopped
    }

    func masterFd(for profileId: UUID) -> Int32? {
        _ = stateVersion
        return processes[profileId]?.pty.masterFd
    }

    var allProfileIds: [UUID] {
        Array(processes.keys)
    }

    func startProfile(
        _ profile: Profile,
        path: String,
        env: [String: String] = [:],
        onStarted: (() -> Void)? = nil
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                var environment = ProcessInfo.processInfo.environment
                environment["PATH"] = path
                for (key, value) in profile.env.merging(env, uniquingKeysWith: { _, new in new }) {
                    environment[key] = value
                }

                let pty = try PTYManager.spawnShell(
                    shellCommand: profile.command,
                    environment: environment,
                    workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path
                )

                var managed = ManagedProcess(
                    profileId: profile.id,
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
                    self?.handleProcessExit(profileId: profile.id, profile: profile, path: path)
                }
                source.resume()
                managed.processSource = source

                DispatchQueue.main.async {
                    self.processes[profile.id] = managed
                    self.notifyStateChange()
                    onStarted?()
                }
            } catch {
                DispatchQueue.main.async {
                    self.processes[profile.id] = ManagedProcess(
                        profileId: profile.id,
                        pty: PTYProcess(pid: -1, masterFd: -1),
                        status: .crashed
                    )
                    self.notifyStateChange()
                }
            }
        }
    }

    func stopProfile(_ profileId: UUID, onStopped: (() -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else { return }
            guard var managed = self.processes[profileId] else {
                DispatchQueue.main.async { onStopped?() }
                return
            }

            managed.isStoppedByUser = true
            self.processes[profileId]?.isStoppedByUser = true
            managed.processSource?.cancel()
            self.processes[profileId]?.processSource = nil

            let pid = managed.pty.pid
            if pid > 0 {
                kill(pid, SIGTERM)

                self.queue.asyncAfter(deadline: .now() + 5) { [weak self] in
                    var status: Int32 = 0
                    let result = waitpid(pid, &status, WNOHANG)
                    if result == 0 {
                        kill(pid, SIGKILL)
                        waitpid(pid, &status, WNOHANG)
                    }
                    managed.pty.cleanup()
                    DispatchQueue.main.async {
                        self?.processes[profileId]?.status = .stopped
                        self?.processes[profileId]?.isStoppedByUser = true
                        self?.notifyStateChange()
                        onStopped?()
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.processes[profileId]?.status = .stopped
                    self.notifyStateChange()
                    onStopped?()
                }
            }
        }
    }

    func restartProfile(_ profile: Profile, path: String) {
        stopProfile(profile.id) { [weak self] in
            self?.startProfile(profile, path: path)
        }
    }

    func stopAll(onComplete: (() -> Void)? = nil) {
        let group = DispatchGroup()
        for id in Array(processes.keys) {
            group.enter()
            stopProfile(id) { group.leave() }
        }
        group.notify(queue: .main) { onComplete?() }
    }

    // MARK: - Terminal Tabs (no keepalive)

    func spawnTerminal() -> (UUID, Int32)? {
        let id = UUID()
        do {
            let pty = try PTYManager.spawnInteractiveShell()
            let managed = ManagedProcess(profileId: id, pty: pty, status: .running)
            processes[id] = managed
            return (id, pty.masterFd)
        } catch {
            return nil
        }
    }

    func closeTerminal(_ id: UUID) {
        guard let managed = processes[id] else { return }
        if managed.pty.pid > 0 { kill(managed.pty.pid, SIGTERM) }
        managed.pty.cleanup()
        managed.processSource?.cancel()
        processes.removeValue(forKey: id)
    }

    func isTerminalRunning(_ id: UUID) -> Bool {
        guard let managed = processes[id], managed.pty.pid > 0 else { return false }
        var status: Int32 = 0
        let result = waitpid(managed.pty.pid, &status, WNOHANG)
        return result == 0
    }

    // MARK: - Private

    private func handleProcessExit(profileId: UUID, profile: Profile, path: String) {
        guard var managed = processes[profileId] else { return }

        var status: Int32 = 0
        waitpid(managed.pty.pid, &status, 0)

        let exitCode = wIfExited(status) ? Int(wExitStatus(status)) : -1
        let wasSignaled = wIfSignaled(status)

        if managed.isStoppedByUser { return }

        if exitCode == 0 && !wasSignaled {
            DispatchQueue.main.async { [weak self] in
                self?.processes[profileId]?.status = .stopped
                self?.notifyStateChange()
            }
            return
        }

        let elapsed = Date().timeIntervalSince(managed.lastStartTime)
        if elapsed < 1.0 {
            managed.consecutiveQuickCrashes += 1
        } else {
            managed.consecutiveQuickCrashes = 0
        }

        let isCrashLooping = managed.consecutiveQuickCrashes >= 10

        DispatchQueue.main.async { [weak self] in
            self?.processes[profileId]?.status = isCrashLooping ? .crashLooping : .crashed
            self?.processes[profileId]?.consecutiveQuickCrashes = managed.consecutiveQuickCrashes
            if isCrashLooping { self?.onCrashLoop?(profileId, profile.name) }
        }

        let delay = self.restartDelay
        queue.asyncAfter(deadline: .now() + .seconds(delay)) { [weak self] in
            guard let self else { return }
            guard let current = self.processes[profileId], !current.isStoppedByUser else { return }

            current.pty.cleanup()
            current.processSource?.cancel()

            do {
                var environment = ProcessInfo.processInfo.environment
                environment["PATH"] = path
                for (key, value) in profile.env { environment[key] = value }

                let newPty = try PTYManager.spawnShell(shellCommand: profile.command, environment: environment)

                let source = DispatchSource.makeProcessSource(identifier: newPty.pid, eventMask: .exit, queue: self.queue)
                source.setEventHandler { [weak self] in
                    self?.handleProcessExit(profileId: profileId, profile: profile, path: path)
                }
                source.resume()

                DispatchQueue.main.async { [weak self] in
                    self?.processes[profileId]?.pty = newPty
                    self?.processes[profileId]?.status = .running
                    self?.processes[profileId]?.processSource = source
                    self?.processes[profileId]?.lastStartTime = Date()
                    self?.notifyStateChange()
                    self?.onProcessRestarted?(profileId)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.processes[profileId]?.status = .crashed
                    self?.notifyStateChange()
                }
            }
        }
    }
}
