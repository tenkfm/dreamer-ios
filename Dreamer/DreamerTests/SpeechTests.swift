import AVFoundation
import Foundation
import Testing
@testable import Dreamer

struct TranscriptStitcherTests {
    @Test func segmentsAreJoinedAcrossRecognitionRequests() {
        var stitcher = TranscriptStitcher()
        #expect(stitcher.update(partial: "I was back") == "I was back")
        #expect(stitcher.update(partial: "I was back in my house") == "I was back in my house")
        #expect(stitcher.commit("I was back in my grandmother's house.") == "I was back in my grandmother's house.")
        // A new request after the ~1 minute limit starts empty and continues the text.
        #expect(stitcher.update(partial: "The hallway") == "I was back in my grandmother's house. The hallway")
        #expect(stitcher.commit("The hallway kept getting longer.") == "I was back in my grandmother's house. The hallway kept getting longer.")
        #expect(stitcher.partial.isEmpty)
    }

    @Test func emptySegmentsAddNoSpaces() {
        var stitcher = TranscriptStitcher()
        #expect(stitcher.commit("") == "")
        #expect(stitcher.update(partial: "  ") == "")
        #expect(stitcher.commit("Hello") == "Hello")
        #expect(stitcher.commit(" ") == "Hello")
    }
}

struct AudioLevelMeterTests {
    @Test func silenceIsZeroAndLoudSpeechIsHigh() {
        var meter = AudioLevelMeter(interval: 0)
        #expect(meter.level(rms: 0, now: 1) == 0)
        // 0.5 RMS is -6 dBFS: 44 of the 50 dB above the floor.
        let loud = meter.level(rms: 0.5, now: 2) ?? 0
        #expect(abs(loud - 0.88) < 0.01)
    }

    @Test func levelFallsSlowlyAfterASyllable() {
        var meter = AudioLevelMeter(interval: 0)
        _ = meter.level(rms: 0.5, now: 1)
        let after = meter.level(rms: 0, now: 2)
        #expect((after ?? 0) > 0.5)
    }

    @Test func levelsAreThrottled() {
        var meter = AudioLevelMeter(interval: 0.05)
        #expect(meter.level(rms: 0.1, now: 1.00) != nil)
        #expect(meter.level(rms: 0.1, now: 1.02) == nil)
        #expect(meter.level(rms: 0.1, now: 1.06) != nil)
    }

    @Test func pcmBufferIsMeasured() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160))
        buffer.frameLength = 160
        for i in 0..<160 { buffer.floatChannelData![0][i] = i.isMultiple(of: 2) ? 0.25 : -0.25 }
        var meter = AudioLevelMeter(interval: 0)
        let level = meter.level(of: buffer, now: 1) ?? 0
        #expect(level > 0.7 && level < 0.9)
    }
}

@MainActor
struct RecordViewModelSpeechTests {
    /// Emits the scripted events, then fails or ends.
    final class ScriptedSpeech: SpeechService {
        var events: [SpeechEvent]
        var failure: SpeechError?
        private(set) var stopped = 0
        init(events: [SpeechEvent], failure: SpeechError? = nil) { self.events = events; self.failure = failure }
        func start() -> AsyncThrowingStream<SpeechEvent, any Error> {
            AsyncThrowingStream { continuation in
                for event in events { continuation.yield(event) }
                if let failure { continuation.finish(throwing: failure) }
            }
        }
        func stop() { stopped += 1 }
    }

    @Test func transcriptAndLevelsReachTheScreen() async throws {
        let speech = ScriptedSpeech(events: [.level(0.2), .transcript("I was"), .level(0.9), .transcript("I was back")])
        let viewModel = RecordViewModel(speech: speech)
        viewModel.start()
        try await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.transcript == "I was back")
        let lastTwo = Array(viewModel.levels.suffix(2))
        #expect(abs(lastTwo[0] - 0.2) < 0.001 && abs(lastTwo[1] - 0.9) < 0.001)
        #expect(viewModel.levels.count == RecordViewModel.barCount)
        viewModel.stop()
    }

    @Test func recognitionFailureStopsRecordingAndKeepsTheText() async throws {
        let speech = ScriptedSpeech(events: [.transcript("Half a dream")], failure: .unavailable)
        let viewModel = RecordViewModel(speech: speech)
        viewModel.start()
        try await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.speechError == .unavailable)
        #expect(!viewModel.isRecording)
        #expect(viewModel.transcript == "Half a dream")
    }
}

@MainActor
struct MicrophonePermissionTests {
    @Test func grantedStartsListeningAtOnce() {
        let viewModel = RecordViewModel(speech: RecordViewModelSpeechTests.ScriptedSpeech(events: []),
                                        permissions: MockSpeechPermissions(current: .granted))
        viewModel.appeared()
        #expect(viewModel.access == .listening)
        #expect(viewModel.isRecording)
        viewModel.stop()
    }

    @Test func firstTimeShowsThePrePromptBeforeTheSystemAlert() async {
        let permissions = MockSpeechPermissions(current: .notDetermined, answer: .granted)
        let viewModel = RecordViewModel(speech: RecordViewModelSpeechTests.ScriptedSpeech(events: []), permissions: permissions)

        viewModel.appeared()
        #expect(viewModel.access == .prePrompt)
        #expect(permissions.requests == 0)
        #expect(!viewModel.isRecording)

        await viewModel.requestAccess()
        #expect(permissions.requests == 1)
        #expect(viewModel.access == .listening)
        viewModel.stop()
    }

    @Test func refusalOffersTypingAndSettings() async {
        let viewModel = RecordViewModel(speech: RecordViewModelSpeechTests.ScriptedSpeech(events: []),
                                        permissions: MockSpeechPermissions(current: .notDetermined, answer: .denied))
        viewModel.appeared()
        await viewModel.requestAccess()
        #expect(viewModel.access == .blocked(.denied))

        viewModel.typeInstead()
        #expect(viewModel.isTyping)
        #expect(!viewModel.isRecording)
    }

    @Test func permissionsCombineMicrophoneAndSpeech() {
        #expect(SystemSpeechPermissions.combine(microphone: .granted, speech: .authorized) == .granted)
        #expect(SystemSpeechPermissions.combine(microphone: .denied, speech: .authorized) == .denied)
        #expect(SystemSpeechPermissions.combine(microphone: .granted, speech: .denied) == .denied)
        #expect(SystemSpeechPermissions.combine(microphone: .undetermined, speech: .authorized) == .notDetermined)
        #expect(SystemSpeechPermissions.combine(microphone: .granted, speech: .restricted) == .restricted)
    }
}
