import AVFoundation
import AppKit
import ApplicationServices
import Foundation

final class PermissionsChecker: ObservableObject {
    enum State { case ok, missing, unknown }

    @Published var microphone: State = .unknown
    @Published var accessibility: State = .unknown
    @Published var whisperBinary: State = .unknown
    @Published var whisperModel: State = .unknown

    var allGood: Bool {
        microphone == .ok && accessibility == .ok
            && whisperBinary == .ok && whisperModel == .ok
    }

    func refresh(config: AppConfig) {
        microphone = micState()
        accessibility = AXIsProcessTrusted() ? .ok : .missing
        whisperBinary = FileManager.default.isExecutableFile(atPath: config.whisperBinary) ? .ok : .missing
        whisperModel = FileManager.default.fileExists(atPath: config.whisperModel) ? .ok : .missing
    }

    func requestMicrophone() async {
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        microphone = micState()
    }

    func promptAccessibility() {
        let opts: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    func openAccessibilityPane() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openMicrophonePane() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    private func micState() -> State {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .ok
        case .notDetermined: return .unknown
        default: return .missing
        }
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
