import Foundation

final class ProcessManager {
    func stopAll(onComplete: (() -> Void)? = nil) {
        onComplete?()
    }
}
