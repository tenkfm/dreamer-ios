import Foundation
import Testing
@testable import Dreamer

struct TrackingPlanTests {
    /// Every client event, once.
    static let allEvents: [AnalyticsEvent] = [
        .onboardingStepViewed(step: .quizGoal), .quizAnswered(.goal(.recurring)), .quizAnswered(.lens(.spiritual)),
        .paywallViewed(placement: .limit, variant: "oneFree"), .planSelected(plan: .yearly), .purchaseStarted(plan: .weekly),
        .signInStarted(method: .apple), .recordStarted, .recordFinished(seconds: 42, input: .voice),
        .detailsSubmitted(skipped: false, emotionsCount: 2), .interpretationViewed(lens: .psychology),
        .lensPromoted(from: .psychology, to: .dreamBook), .readAloudPlayed(lens: .spiritual, fallback: false),
        .readAloudCompleted(lens: .spiritual, fallback: true, listenedPct: 64), .readAloudFallback(lens: .spiritual, reason: .network),
        .dreamShared(target: .photos), .journalOpened, .librarySymbolOpened(slug: "teeth"), .pushOpened(type: "dream_ready")
    ]

    @Test func namesAreTheTrackingPlans() {
        let names = Set(Self.allEvents.map(\.name))
        #expect(names == ["onboarding_step_viewed", "quiz_answered", "paywall_viewed", "plan_selected", "purchase_started",
                          "sign_in_started", "record_started", "record_finished", "details_submitted", "interpretation_viewed",
                          "lens_promoted", "read_aloud_played", "read_aloud_completed", "read_aloud_fallback", "dream_shared",
                          "journal_opened", "library_symbol_opened", "push_opened"])
    }

    @Test func numbersAndBooleansKeepTheirTypes() {
        #expect(AnalyticsEvent.recordFinished(seconds: 42, input: .text).properties == ["seconds": .int(42), "input": .string("text")])
        #expect(AnalyticsEvent.detailsSubmitted(skipped: true, emotionsCount: 9).properties
                == ["skipped": .bool(true), "emotionsCount": .int(5)])
        #expect(AnalyticsEvent.readAloudCompleted(lens: .spiritual, fallback: false, listenedPct: 130).properties["listenedPct"] == .int(100))
        #expect(AnalyticsEvent.onboardingStepViewed(step: .quizLens).properties == ["step": .string("quizLens")])
    }

    @Test func noPersonalContentIsEverAProperty() {
        // FORBIDDEN_PROPERTY_KEYS of the backend's analyticsProperties().
        let forbidden: Set<String> = ["text", "title", "notes", "email", "name", "token", "transcript", "snippet"]
        for event in Self.allEvents {
            #expect(Set(event.properties.keys).isDisjoint(with: forbidden), "\(event.name)")
        }
        #expect(Set(AnalyticsContext(preferredLens: .spiritual, paywallVariant: .hard).properties.keys)
                == ["preferred_lens", "paywall_variant"])
    }

    @Test func paywallPlacementsMapToThePlan() {
        #expect(PaywallViewModel.Placement.gate.analytics == .onboarding)
        #expect(PaywallViewModel.Placement.analysis.analytics == .limit)
        #expect(PaywallViewModel.Placement.record.analytics == .limit)
        #expect(PaywallViewModel.Placement.settings.analytics == .settings)
    }
}

@MainActor
struct CoreLoopEventTests {
    @Test func recordingStartsOnceAndFinishesAsVoice() async throws {
        let analytics = RecordingAnalytics()
        let viewModel = RecordViewModel(speech: RecordViewModelSpeechTests.ScriptedSpeech(events: [.transcript("I was flying")]),
                                        analytics: analytics)
        viewModel.start()
        try await Task.sleep(for: .milliseconds(20))
        viewModel.pause(.user)
        viewModel.resume()
        try await Task.sleep(for: .milliseconds(20))
        _ = await viewModel.finish()

        #expect(analytics.events == [.recordStarted, .recordFinished(seconds: 0, input: .voice)])
    }

    @Test func aTypedDreamCountsAsText() async {
        let analytics = RecordingAnalytics()
        let viewModel = RecordViewModel(speech: RecordViewModelSpeechTests.ScriptedSpeech(events: []), analytics: analytics)
        viewModel.switchToTyping()
        viewModel.transcript = "Typed dream"
        _ = await viewModel.finish()
        #expect(analytics.events.last == .recordFinished(seconds: 0, input: .text))
    }

    @Test func detailsAreReportedSubmittedOrSkipped() async {
        let analytics = RecordingAnalytics()
        let flow = RecordFlowViewModel(speech: MockSpeechService(), analytics: analytics,
                                       analysisService: MockDreamAnalysisService(stepDuration: .zero),
                                       store: InMemoryDreamStore(seed: []), onFinish: { _ in }, onCancel: {})
        flow.record.transcript = "A hallway"
        await flow.finishRecording()
        flow.interpret(includeDetails: false)
        #expect(analytics.events.last == .detailsSubmitted(skipped: true, emotionsCount: 0))
    }

    @Test func anInterpretationIsReportedOnceAndNeverForACrisisDream() {
        let analytics = RecordingAnalytics()
        let store = InMemoryDreamStore()
        let appState = AppState(store: InMemoryPreferencesStore())
        let viewModel = InterpretationViewModel(dreamID: store.dreams[0].id, store: store, appState: appState,
                                                readAloud: MockReadAloudService(), imageSaver: MockImageSaver(), analytics: analytics)
        viewModel.viewed()
        viewModel.viewed()
        #expect(analytics.events == [.interpretationViewed(lens: .psychology)])

        var crisis = store.dreams[1]
        crisis.interpretation?.safetyFlag = true
        store.save(crisis)
        let crisisAnalytics = RecordingAnalytics()
        InterpretationViewModel(dreamID: crisis.id, store: store, appState: appState, readAloud: MockReadAloudService(),
                                imageSaver: MockImageSaver(), analytics: crisisAnalytics).viewed()
        #expect(crisisAnalytics.events.isEmpty)
    }

    @Test func openingTheJournalIsReported() {
        let analytics = RecordingAnalytics()
        JournalViewModel(appState: AppState(store: InMemoryPreferencesStore()), store: InMemoryDreamStore(), analytics: analytics).opened()
        #expect(analytics.events == [.journalOpened])
    }

    @Test func stoppingTheVoiceReportsHowMuchWasHeard() {
        let analytics = RecordingAnalytics()
        let playback = FakePlayback()
        let service = BackendReadAloudService(source: ScriptedAudioSource(), fallback: MockReadAloudService(), playback: playback,
                                              analytics: analytics)
        let audio = DreamAudio(lens: .spiritual, status: .ready, url: URL(string: "https://media.test/a.mp3"), duration: 10,
                               wordTimings: [WordTiming(word: "a", start: 0, end: 10)])
        service.play(ReadAloudItem(text: "a", lens: .spiritual, dreamID: UUID(), audio: audio))
        playback.onTime?(4)
        service.stop()
        #expect(analytics.events.last == .readAloudCompleted(lens: .spiritual, fallback: false, listenedPct: 40))
    }
}
