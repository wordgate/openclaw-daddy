import Foundation
import AVFoundation
import CoreLocation
import UserNotifications
import AppKit

enum PermissionStatus: String {
    case granted = "Granted"
    case denied = "Denied"
    case notAsked = "Not Asked"
    case unknown = "Unknown"
}

struct PermissionInfo: Identifiable {
    let id: String
    let name: String
    var status: PermissionStatus
    let canRequest: Bool
    let canDetect: Bool
    let settingsURL: String?
}

final class PermissionManager: ObservableObject {
    @Published var permissions: [PermissionInfo] = []
    private let locationManager = CLLocationManager()

    init() { refresh() }

    func refresh() {
        permissions = [
            screenRecordingPermission(),
            accessibilityPermission(),
            cameraPermission(),
            microphonePermission(),
            fullDiskAccessPermission(),
            inputMonitoringPermission(),
        ]
    }

    func request(_ id: String) {
        switch id {
        case "camera":
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
                DispatchQueue.main.async { self?.refresh() }
            }
        case "microphone":
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                DispatchQueue.main.async { self?.refresh() }
            }
        case "screen_recording":
            CGRequestScreenCaptureAccess()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.refresh() }
        case "location":
            locationManager.requestWhenInUseAuthorization()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.refresh() }
        default: break
        }
    }

    func openSettings(_ urlString: String) {
        if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
    }

    private func screenRecordingPermission() -> PermissionInfo {
        PermissionInfo(id: "screen_recording", name: "Screen Recording",
                      status: CGPreflightScreenCaptureAccess() ? .granted : .denied,
                      canRequest: true, canDetect: true,
                      settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    private func accessibilityPermission() -> PermissionInfo {
        PermissionInfo(id: "accessibility", name: "Accessibility",
                      status: AXIsProcessTrusted() ? .granted : .denied,
                      canRequest: false, canDetect: true,
                      settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private func cameraPermission() -> PermissionInfo {
        let s = AVCaptureDevice.authorizationStatus(for: .video)
        return PermissionInfo(id: "camera", name: "Camera", status: avStatus(s),
                            canRequest: s == .notDetermined, canDetect: true,
                            settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
    }

    private func microphonePermission() -> PermissionInfo {
        let s = AVCaptureDevice.authorizationStatus(for: .audio)
        return PermissionInfo(id: "microphone", name: "Microphone", status: avStatus(s),
                            canRequest: s == .notDetermined, canDetect: true,
                            settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    private func fullDiskAccessPermission() -> PermissionInfo {
        PermissionInfo(id: "full_disk", name: "Full Disk Access", status: .unknown,
                      canRequest: false, canDetect: false,
                      settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }

    private func inputMonitoringPermission() -> PermissionInfo {
        PermissionInfo(id: "input_monitoring", name: "Input Monitoring", status: .unknown,
                      canRequest: false, canDetect: false,
                      settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private func avStatus(_ s: AVAuthorizationStatus) -> PermissionStatus {
        switch s {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notAsked
        @unknown default: return .unknown
        }
    }
}
