import Foundation

final class LogManager {
    private var fileHandles: [UUID: FileHandle] = [:]
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    func startLogging(profileId: UUID, logFilePath: String) {
        let expanded = NSString(string: logFilePath).expandingTildeInPath
        let dir = (expanded as NSString).deletingLastPathComponent
        let baseName = ((expanded as NSString).lastPathComponent as NSString).deletingPathExtension
        let ext = (expanded as NSString).pathExtension
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let dateString = dateFormatter.string(from: Date())
        let rotatedPath = "\(dir)/\(baseName)-\(dateString).\(ext.isEmpty ? "log" : ext)"
        FileManager.default.createFile(atPath: rotatedPath, contents: nil)
        if let handle = FileHandle(forWritingAtPath: rotatedPath) {
            handle.seekToEndOfFile()
            fileHandles[profileId] = handle
        }
    }

    func write(profileId: UUID, data: Data) { fileHandles[profileId]?.write(data) }
    func stopLogging(profileId: UUID) { fileHandles[profileId]?.closeFile(); fileHandles.removeValue(forKey: profileId) }
    func stopAll() { for id in fileHandles.keys { stopLogging(profileId: id) } }
}
