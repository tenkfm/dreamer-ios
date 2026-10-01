@preconcurrency import AVFoundation
import Foundation
@preconcurrency import Speech

/// Microphone plus speech recognition, as one answer: recording a dream needs both.
enum SpeechPermission: Equatable, Sendable {
    /// Never asked: show the pre-prompt before the system alerts.
    case notDetermined
    case granted
    /// Refused: only Settings can change it.
    case denied
    /// Blocked by parental controls or MDM.
    case restricted
}

@MainActor
protocol SpeechPermissions: AnyObject {
    var current: SpeechPermission { get }
    /// Shows the system alerts that have not been answered yet.
    func request() async -> SpeechPermission
}

@MainActor
final class SystemSpeechPermissions: SpeechPermissions {
    var current: SpeechPermission {
        Self.combine(microphone: Self.microphone, speech: SFSpeechRecognizer.authorizationStatus())
    }

    func request() async -> SpeechPermission {
        if Self.microphone == .undetermined {
            _ = await AVAudioApplication.requestRecordPermission()
        }
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            _ = await Self.requestSpeechAuthorization()
        }
        return current
    }

    /// Speech calls back on a background queue. A closure written inside this @MainActor class is
    /// main-actor isolated, and Swift 6 traps when it runs elsewhere: the app crashed right after
    /// the user allowed the microphone and speech. Nonisolated, with a @Sendable callback, it may
    /// run on any queue.
    nonisolated private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { @Sendable status in continuation.resume(returning: status) }
        }
    }

    private static var microphone: AVAudioApplication.recordPermission {
        AVAudioApplication.shared.recordPermission
    }

    static func combine(microphone: AVAudioApplication.recordPermission,
                        speech: SFSpeechRecognizerAuthorizationStatus) -> SpeechPermission {
        if microphone == .denied || speech == .denied { return .denied }
        if speech == .restricted { return .restricted }
        if microphone == .granted && speech == .authorized { return .granted }
        return .notDetermined
    }
}

/// For previews, tests and mock mode.
@MainActor
final class MockSpeechPermissions: SpeechPermissions {
    var current: SpeechPermission
    var answer: SpeechPermission
    private(set) var requests = 0

    init(current: SpeechPermission = .granted, answer: SpeechPermission = .granted) {
        self.current = current
        self.answer = answer
    }

    func request() async -> SpeechPermission {
        requests += 1
        current = answer
        return answer
    }
}
