@preconcurrency import AVFoundation
import Foundation
import Observation

/// The backend's voice-overs of a dream's lenses (`/v1/dreams/{id}/audio?lens=`).
protocol DreamAudioSource: Sendable {
    func dreamAudio(id dreamID: UUID, lens: Lens) async throws(APIError) -> DreamAudio
    /// Starts the voice-over (or joins the running job); `pending` means poll `dreamAudio`.
    func requestDreamAudio(id dreamID: UUID, lens: Lens) async throws(APIError) -> DreamAudio
}

extension APIClient: DreamAudioSource {}

/// Plays one audio file. AVPlayer in the app; a fake in tests.
@MainActor
protocol VoicePlayback: AnyObject {
    /// Starts buffering (before the tap, for the main lens).
    func load(_ url: URL)
    var loadedURL: URL? { get }
    func play()
    func pause()
    func stop()
    /// Seconds played, about 10 times a second.
    var onTime: ((TimeInterval) -> Void)? { get set }
    var onEnd: (() -> Void)? { get set }
    /// The file could not be played (a presigned link that expired, no connection).
    var onFailure: (() -> Void)? { get set }
}

/// Reads the interpretation in the backend's ElevenLabs voice. The main lens is voiced with the
/// dream, so it plays at once (and is buffered when the screen opens); another lens is asked for
/// and polled until ready. With the voice unavailable (TTS off, `TTS_UNAVAILABLE`, a failed job, no
/// connection) the on-device voice reads instead, and the fallback is reported.
@MainActor
@Observable
final class BackendReadAloudService: ReadAloudService {
    var state: ReadAloudState { usingFallback ? fallback.state : ownState }
    var progress: Double { usingFallback ? fallback.progress : ownProgress }
    @ObservationIgnored var onFinish: (@MainActor () -> Void)?

    private var ownState: ReadAloudState = .idle
    private var ownProgress: Double = 0
    private var usingFallback = false

    @ObservationIgnored private let source: any DreamAudioSource
    @ObservationIgnored private let fallback: any ReadAloudService
    @ObservationIgnored private let playback: any VoicePlayback
    @ObservationIgnored private let analytics: any Analytics
    @ObservationIgnored private let ttsEnabled: Bool
    @ObservationIgnored private let pollInterval: Duration
    @ObservationIgnored private var current: ReadAloudItem?
    @ObservationIgnored private var currentAudio: DreamAudio?
    @ObservationIgnored private var retriedLink = false
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    /// About 30 s for a lens to be voiced.
    static let maxPolls = 30

    init(source: any DreamAudioSource,
         fallback: any ReadAloudService,
         playback: any VoicePlayback,
         analytics: any Analytics = NoopAnalytics(),
         ttsEnabled: Bool = true,
         pollInterval: Duration = .seconds(1)) {
        self.source = source
        self.fallback = fallback
        self.playback = playback
        self.analytics = analytics
        self.ttsEnabled = ttsEnabled
        self.pollInterval = pollInterval
        playback.onTime = { [weak self] seconds in self?.played(seconds) }
        playback.onEnd = { [weak self] in self?.reachedEnd() }
        playback.onFailure = { [weak self] in self?.playbackFailed() }
    }

    func prepare(_ item: ReadAloudItem) {
        guard ttsEnabled, current == nil, let url = Self.readyURL(item.audio), playback.loadedURL != url else { return }
        playback.load(url)
    }

    func play(_ item: ReadAloudItem) {
        if item == current, state == .paused {
            usingFallback ? fallback.play(item) : resume()
            return
        }
        stop()
        current = item
        guard ttsEnabled else {
            // Switched off by the flag: the same as the voice being unavailable.
            readOnDevice(item, reason: .ttsUnavailable)
            return
        }
        guard let dreamID = item.dreamID else {
            readOnDevice(item, reason: .audioFailed)
            return
        }
        if let audio = item.audio, Self.readyURL(audio) != nil {
            start(audio, for: item)
            return
        }
        ownState = .loading
        loadTask = Task { [weak self] in
            await self?.fetchAndPlay(item, dreamID: dreamID)
        }
    }

    func pause() {
        if usingFallback {
            fallback.pause()
        } else if ownState == .playing {
            playback.pause()
            ownState = .paused
        }
    }

    func stop() {
        reportStopped()
        loadTask?.cancel()
        loadTask = nil
        if usingFallback { fallback.stop() }
        if current != nil { playback.stop() }
        usingFallback = false
        current = nil
        currentAudio = nil
        retriedLink = false
        ownState = .idle
        ownProgress = 0
    }

    /// Stopped before the end: how much was heard ("completed" in the plan covers both).
    private func reportStopped() {
        guard let item = current, state == .playing || state == .paused, progress > 0 else { return }
        analytics.track(.readAloudCompleted(lens: item.lens, fallback: usingFallback,
                                            listenedPct: Int((progress * 100).rounded())))
    }

    // MARK: Backend voice

    private func fetchAndPlay(_ item: ReadAloudItem, dreamID: UUID) async {
        do {
            let audio = try await readyAudio(dreamID: dreamID, lens: item.lens)
            guard current == item, !Task.isCancelled else { return }
            start(audio, for: item)
        } catch {
            guard current == item, !Task.isCancelled else { return }
            readOnDevice(item, reason: Self.reason(for: error))
        }
    }

    /// Asks for the voice-over and waits while it is made.
    private func readyAudio(dreamID: UUID, lens: Lens) async throws(APIError) -> DreamAudio {
        var audio = try await source.requestDreamAudio(id: dreamID, lens: lens)
        var polls = 0
        while audio.status == .pending {
            guard polls < Self.maxPolls else { throw APIError.timeout }
            try? await Task.sleep(for: pollInterval)
            if Task.isCancelled { throw APIError.timeout }
            polls += 1
            audio = try await source.dreamAudio(id: dreamID, lens: lens)
        }
        guard Self.readyURL(audio) != nil else {
            throw APIError.server(.init(code: .ttsUnavailable, message: "", status: 503))
        }
        return audio
    }

    private func start(_ audio: DreamAudio, for item: ReadAloudItem) {
        guard let url = Self.readyURL(audio) else { return }
        currentAudio = audio
        activateAudioSession()
        if playback.loadedURL != url { playback.load(url) }
        playback.play()
        ownProgress = 0
        ownState = .playing
        analytics.track(.readAloudPlayed(lens: item.lens, fallback: false))
    }

    private func resume() {
        playback.play()
        ownState = .playing
    }

    /// Progress along the word timings (they end where the last word does, not at trailing silence).
    private func played(_ seconds: TimeInterval) {
        guard ownState == .playing, let audio = currentAudio else { return }
        let total = audio.wordTimings.last?.end ?? audio.duration ?? 0
        guard total > 0 else { return }
        ownProgress = min(max(seconds / total, 0), 1)
    }

    private func reachedEnd() {
        guard let item = current, !usingFallback else { return }
        ownProgress = 1
        ownState = .idle
        current = nil
        currentAudio = nil
        playback.stop()
        analytics.track(.readAloudCompleted(lens: item.lens, fallback: false, listenedPct: 100))
        onFinish?()
    }

    /// A presigned link expires: ask for the voice again once, then read on the device.
    private func playbackFailed() {
        guard let item = current, !usingFallback else { return }
        playback.stop()
        guard !retriedLink, let dreamID = item.dreamID else {
            readOnDevice(item, reason: .audioFailed)
            return
        }
        retriedLink = true
        ownState = .loading
        loadTask = Task { [weak self] in
            await self?.fetchAndPlay(item, dreamID: dreamID)
        }
    }

    // MARK: On-device voice

    private func readOnDevice(_ item: ReadAloudItem, reason: ReadAloudFallbackReason) {
        ownState = .idle
        usingFallback = true
        analytics.track(.readAloudFallback(lens: item.lens, reason: reason))
        fallback.onFinish = { [weak self] in
            guard let self, self.usingFallback else { return }
            self.analytics.track(.readAloudCompleted(lens: item.lens, fallback: true, listenedPct: 100))
            self.onFinish?()
        }
        fallback.play(item)
        analytics.track(.readAloudPlayed(lens: item.lens, fallback: true))
    }

    private static func readyURL(_ audio: DreamAudio?) -> URL? {
        guard let audio, audio.status == .ready else { return nil }
        return audio.url
    }

    private static func reason(for error: APIError) -> ReadAloudFallbackReason {
        switch error {
        case .offline: .network
        case .timeout: .timeout
        case .server(let server) where server.code == .ttsUnavailable: .ttsUnavailable
        default: .audioFailed
        }
    }

    private func activateAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}

/// AVPlayer behind `VoicePlayback`.
@MainActor
final class AVVoicePlayback: VoicePlayback {
    var onTime: ((TimeInterval) -> Void)?
    var onEnd: (() -> Void)?
    var onFailure: (() -> Void)?
    private(set) var loadedURL: URL?

    private let player = AVPlayer()
    /// Set once in init, read in deinit (which runs off the main actor).
    nonisolated(unsafe) private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?

    init() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.onTime?(time.seconds) }
        }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
    }

    func load(_ url: URL) {
        removeItemObservers()
        let item = AVPlayerItem(url: url)
        loadedURL = url
        let center = NotificationCenter.default
        endObserver = center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onEnd?() }
        }
        failureObserver = center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onFailure?() }
        }
        statusObservation = item.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in self?.onFailure?() }
        }
        player.replaceCurrentItem(with: item)
    }

    func play() { player.play() }

    func pause() { player.pause() }

    func stop() {
        player.pause()
        removeItemObservers()
        player.replaceCurrentItem(with: nil)
        loadedURL = nil
    }

    private func removeItemObservers() {
        [endObserver, failureObserver].compactMap { $0 }.forEach(NotificationCenter.default.removeObserver)
        endObserver = nil
        failureObserver = nil
        statusObservation = nil
    }
}
