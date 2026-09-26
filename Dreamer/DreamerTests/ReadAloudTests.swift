import Foundation
import os
import Testing
@testable import Dreamer

@MainActor
final class FakePlayback: VoicePlayback {
    var onTime: ((TimeInterval) -> Void)?
    var onEnd: (() -> Void)?
    var onFailure: (() -> Void)?
    private(set) var loadedURL: URL?
    private(set) var loads: [URL] = []
    private(set) var isPlaying = false

    func load(_ url: URL) { loadedURL = url; loads.append(url) }
    func play() { isPlaying = true }
    func pause() { isPlaying = false }
    func stop() { isPlaying = false; loadedURL = nil }
}

/// Answers the audio endpoints from a script; records the calls.
final class ScriptedAudioSource: DreamAudioSource, @unchecked Sendable {
    private let state: OSAllocatedUnfairLock<(requests: [Result<DreamAudio, APIError>], polls: [Result<DreamAudio, APIError>], calls: [String])>

    init(request: [Result<DreamAudio, APIError>] = [], polls: [Result<DreamAudio, APIError>] = []) {
        state = OSAllocatedUnfairLock(initialState: (request, polls, []))
    }

    var calls: [String] { state.withLock { $0.calls } }

    func requestDreamAudio(id dreamID: UUID, lens: Lens) async throws(APIError) -> DreamAudio {
        try state.withLock { $0.calls.append("POST \(lens.rawValue)"); return $0.requests.removeFirst() }.get()
    }

    func dreamAudio(id dreamID: UUID, lens: Lens) async throws(APIError) -> DreamAudio {
        try state.withLock { $0.calls.append("GET \(lens.rawValue)"); return $0.polls.removeFirst() }.get()
    }
}

@MainActor
struct BackendReadAloudTests {
    private let dreamID = UUID()
    private let url = URL(string: "https://media.test/spiritual.mp3?sig=1")!

    private func audio(_ status: MediaStatus, lens: Lens = .spiritual, url: URL? = nil) -> DreamAudio {
        DreamAudio(lens: lens, status: status, url: status == .ready ? (url ?? self.url) : nil, duration: 5,
                   wordTimings: [WordTiming(word: "Stairs", start: 0, end: 1.5), WordTiming(word: "often", start: 1.6, end: 4)])
    }

    private func item(_ lens: Lens = .spiritual, audio: DreamAudio? = nil) -> ReadAloudItem {
        ReadAloudItem(text: "Stairs often.", lens: lens, dreamID: dreamID, audio: audio)
    }

    private func make(source: ScriptedAudioSource = ScriptedAudioSource(), ttsEnabled: Bool = true)
    -> (BackendReadAloudService, FakePlayback, MockReadAloudService, RecordingAnalytics) {
        let playback = FakePlayback()
        let fallback = MockReadAloudService()
        let analytics = RecordingAnalytics()
        let service = BackendReadAloudService(source: source, fallback: fallback, playback: playback, analytics: analytics,
                                              ttsEnabled: ttsEnabled, pollInterval: .milliseconds(2))
        return (service, playback, fallback, analytics)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
    }

    @Test func theMainLensPlaysAtOnceFromTheBufferedVoice() {
        let source = ScriptedAudioSource()
        let (service, playback, _, analytics) = make(source: source)
        let main = item(audio: audio(.ready))

        service.prepare(main)
        #expect(playback.loads == [url])
        service.play(main)

        #expect(service.state == .playing)
        #expect(playback.isPlaying)
        #expect(playback.loads == [url])
        #expect(source.calls.isEmpty)
        #expect(analytics.events == [.readAloudPlayed(lens: .spiritual, fallback: false)])
    }

    @Test func anotherLensIsVoicedThenPlayed() async {
        let source = ScriptedAudioSource(request: [.success(audio(.pending))], polls: [.success(audio(.pending)), .success(audio(.ready))])
        let (service, playback, _, _) = make(source: source)

        service.play(item())
        #expect(service.state == .loading)
        await waitUntil { service.state == .playing }

        #expect(service.state == .playing)
        #expect(playback.loadedURL == url)
        #expect(source.calls == ["POST spiritual", "GET spiritual", "GET spiritual"])
    }

    @Test(arguments: [
        (Result<DreamAudio, APIError>.failure(.server(.init(code: .ttsUnavailable, message: "", status: 503))), ReadAloudFallbackReason.ttsUnavailable),
        (.failure(.offline), .network),
        (.failure(.timeout), .timeout),
        (.failure(.server(.init(code: .internalError, message: "", status: 500))), .audioFailed)
    ])
    func unavailableVoiceReadsOnTheDevice(answer: Result<DreamAudio, APIError>, reason: ReadAloudFallbackReason) async {
        let (service, playback, fallback, analytics) = make(source: ScriptedAudioSource(request: [answer]))

        service.play(item())
        await waitUntil { service.state == .playing }

        #expect(fallback.lastText == "Stairs often.")
        #expect(service.state == .playing)
        #expect(!playback.isPlaying)
        #expect(analytics.events == [.readAloudFallback(lens: .spiritual, reason: reason),
                                     .readAloudPlayed(lens: .spiritual, fallback: true)])
    }

    @Test func aFailedJobReadsOnTheDevice() async {
        let (service, _, fallback, analytics) = make(source: ScriptedAudioSource(request: [.success(audio(.failed))]))
        service.play(item())
        await waitUntil { fallback.lastText != nil }
        #expect(analytics.events.first == .readAloudFallback(lens: .spiritual, reason: .ttsUnavailable))
    }

    @Test func switchedOffVoiceNeverAsksTheBackend() {
        let source = ScriptedAudioSource()
        let (service, playback, fallback, analytics) = make(source: source, ttsEnabled: false)
        service.prepare(item(audio: audio(.ready)))
        service.play(item(audio: audio(.ready)))

        #expect(source.calls.isEmpty)
        #expect(playback.loads.isEmpty)
        #expect(fallback.state == .playing)
        #expect(analytics.events.first == .readAloudFallback(lens: .spiritual, reason: .ttsUnavailable))
    }

    @Test func progressFollowsTheWordTimings() {
        let (service, playback, _, _) = make()
        service.play(item(audio: audio(.ready)))
        playback.onTime?(2)
        #expect(service.progress == 0.5)
    }

    @Test func theEndIsReported() {
        let (service, playback, _, analytics) = make()
        var finished = false
        service.onFinish = { finished = true }
        service.play(item(audio: audio(.ready)))
        playback.onEnd?()

        #expect(service.state == .idle)
        #expect(service.progress == 1)
        #expect(finished)
        #expect(analytics.events.last == .readAloudCompleted(lens: .spiritual, fallback: false, listenedPct: 100))
    }

    @Test func theDeviceVoiceEndIsReportedToo() {
        let (service, _, fallback, analytics) = make(ttsEnabled: false)
        service.play(item())
        fallback.finish()
        #expect(analytics.events.last == .readAloudCompleted(lens: .spiritual, fallback: true, listenedPct: 100))
    }

    @Test func anExpiredLinkIsFetchedAgainOnce() async {
        let fresh = URL(string: "https://media.test/spiritual.mp3?sig=2")!
        let source = ScriptedAudioSource(request: [.success(audio(.ready, url: fresh))])
        let (service, playback, fallback, _) = make(source: source)

        service.play(item(audio: audio(.ready)))
        playback.onFailure?()
        await waitUntil { playback.loadedURL == fresh }
        #expect(service.state == .playing)

        playback.onFailure?()
        #expect(fallback.state == .playing)
    }

    @Test func pauseAndResume() {
        let (service, playback, _, _) = make()
        let main = item(audio: audio(.ready))
        service.play(main)
        service.pause()
        #expect(service.state == .paused)
        #expect(!playback.isPlaying)
        service.play(main)
        #expect(service.state == .playing)
        #expect(playback.loads.count == 1)
    }
}

@MainActor
struct InterpretationVoiceTests {
    @Test func listenSendsTheDreamAndItsVoice() {
        let store = InMemoryDreamStore()
        var dream = store.dreams[0]
        let voice = DreamAudio(lens: .psychology, status: .ready, url: URL(string: "https://media.test/p.mp3"), duration: 71, wordTimings: [])
        dream.audio = [.psychology: voice]
        store.save(dream)
        let readAloud = MockReadAloudService()
        let viewModel = InterpretationViewModel(dreamID: dream.id, store: store, appState: AppState(store: InMemoryPreferencesStore()),
                                                readAloud: readAloud, imageSaver: MockImageSaver())

        viewModel.togglePlayback()

        #expect(readAloud.lastItem == ReadAloudItem(text: viewModel.text(for: .psychology), lens: .psychology,
                                                    dreamID: dream.id, audio: voice))
        #expect(viewModel.durationText == "1:11")
    }
}
