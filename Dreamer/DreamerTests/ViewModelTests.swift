import Foundation
import Testing
@testable import Dreamer

@MainActor
struct OnboardingTests {
    private static func session(isNew: Bool) -> AuthSession {
        AuthSession(accessToken: "a", accessExpiresAt: .now, refreshToken: "r", refreshExpiresAt: .now,
                    userID: "user-1", isNewUser: isNew)
    }

    @Test func quizAnswersAreStoredWhenLeavingTheQuiz() {
        let appState = AppState(store: InMemoryPreferencesStore())
        let analytics = RecordingAnalytics()
        let viewModel = OnboardingViewModel(appState: appState, step: .quizGoal, analytics: analytics)

        viewModel.goal = .recurring
        viewModel.next()
        viewModel.lens = .spiritual
        viewModel.next()

        #expect(viewModel.step == .account)
        #expect(appState.goal == .recurring)
        #expect(appState.preferredLens == .spiritual)
        #expect(appState.rootScreen == .onboarding)
        #expect(analytics.events.contains(.quizAnswered(.goal(.recurring))))
        #expect(analytics.events.contains(.quizAnswered(.lens(.spiritual))))
        #expect(analytics.events.contains(.onboardingStepViewed(step: .quizLens)))
        // The account step is not in the tracking plan (blocker): nothing is sent for it.
        #expect(analytics.events.last == .quizAnswered(.lens(.spiritual)))
    }

    @Test func thePaywallCannotBeReachedWithoutAnAccount() {
        let appState = AppState(store: InMemoryPreferencesStore())
        let viewModel = OnboardingViewModel(appState: appState, step: .account)

        #expect(!viewModel.reachableSteps.contains(.paywall))
        viewModel.go(to: .paywall)
        #expect(viewModel.step == .account)
    }

    @Test func newAccountContinuesToThePaywall() {
        let appState = AppState(store: InMemoryPreferencesStore())
        let viewModel = OnboardingViewModel(appState: appState, step: .account)

        viewModel.signedIn(Self.session(isNew: true))

        #expect(viewModel.step == .paywall)
        #expect(appState.isSignedIn)
        #expect(appState.rootScreen == .onboarding)
    }

    @Test func returningAccountLeavesOnboarding() {
        let appState = AppState(store: InMemoryPreferencesStore())
        let viewModel = OnboardingViewModel(appState: appState)

        viewModel.useExistingAccount()
        #expect(viewModel.step == .account)
        #expect(viewModel.accountMode == .signIn)

        viewModel.signedIn(Self.session(isNew: false))
        #expect(appState.rootScreen == .paywall)
    }

    @Test func signedOutReturningUserStartsOnSignIn() {
        var preferences = UserPreferences()
        preferences.onboardingCompleted = true
        let viewModel = OnboardingViewModel(appState: AppState(store: InMemoryPreferencesStore(preferences)))

        #expect(viewModel.step == .account)
        #expect(viewModel.accountMode == .signIn)
    }

    @Test func skipJumpsToTheQuiz() {
        let viewModel = OnboardingViewModel(appState: AppState(store: InMemoryPreferencesStore()), step: .record)
        viewModel.skipIntro()
        #expect(viewModel.step == .quizGoal)
    }

    @Test func completionIsPersisted() {
        let store = InMemoryPreferencesStore()
        let appState = AppState(store: store)
        appState.signedIn(userID: "user-1", isNewUser: true)
        appState.activateSubscription(.weekly)

        let relaunched = AppState(store: store)
        #expect(relaunched.rootScreen == .main)
        #expect(relaunched.subscription == .active(.weekly))
    }

    @Test func hardPaywallShowsWithoutSubscription() {
        var preferences = UserPreferences()
        preferences.onboardingCompleted = true
        preferences.userID = "user-1"
        #expect(AppState(store: InMemoryPreferencesStore(preferences)).rootScreen == .paywall)
    }

    @Test func lostKeychainSessionSignsOut() {
        var preferences = UserPreferences()
        preferences.onboardingCompleted = true
        preferences.userID = "user-1"
        preferences.subscription = .active(.yearly)
        let appState = AppState(store: InMemoryPreferencesStore(preferences))

        appState.reconcileSession(storedUserID: nil)

        #expect(!appState.isSignedIn)
        #expect(appState.rootScreen == .onboarding)
    }
}

@MainActor
struct NightModeTests {
    private func date(hour: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: hour, minute: 10))!
    }

    @Test func followsTheNinePMSchedule() {
        let appState = AppState(store: InMemoryPreferencesStore(), now: date(hour: 22))
        #expect(appState.isNightMode)

        appState.refreshClock(date(hour: 8))
        #expect(!appState.isNightMode)

        appState.refreshClock(date(hour: 3))
        #expect(appState.isNightMode)
    }

    @Test func scheduleCanBeTurnedOff() {
        var preferences = UserPreferences()
        preferences.reminders.nightModeAfter9 = false
        let appState = AppState(store: InMemoryPreferencesStore(preferences), now: date(hour: 22))
        #expect(!appState.isNightMode)
    }

    @Test func moonButtonHoldsUntilTheScheduleFlips() {
        let appState = AppState(store: InMemoryPreferencesStore(), now: date(hour: 15))
        appState.toggleNightMode()
        #expect(appState.isNightMode)

        appState.refreshClock(date(hour: 18))
        #expect(appState.isNightMode)

        // 9 PM: the schedule turns night on by itself, the manual choice is dropped.
        appState.refreshClock(date(hour: 21))
        #expect(appState.nightModeOverride == nil)
        #expect(appState.isNightMode)
    }
}

@MainActor
struct PaywallTests {
    @Test func purchaseActivatesTheSelectedPlan() async {
        let appState = AppState(store: InMemoryPreferencesStore())
        appState.signedIn(userID: "user-1", isNewUser: true)
        let viewModel = PaywallViewModel(purchases: MockPurchaseService(delay: .zero), appState: appState)
        await viewModel.loadProducts()

        viewModel.selectedPlan = .weekly
        #expect(viewModel.ctaTitle == "Subscribe for $6.99 a week")
        await viewModel.purchase()

        #expect(appState.subscription == .active(.weekly))
        #expect(appState.rootScreen == .main)
        #expect(!viewModel.isPurchasing)
    }

    @Test func restoreWithNothingToRestoreShowsAMessage() async {
        let appState = AppState(store: InMemoryPreferencesStore())
        let viewModel = PaywallViewModel(purchases: MockPurchaseService(delay: .zero, restoredPlan: nil), appState: appState)

        await viewModel.restore()

        #expect(viewModel.alertMessage != nil)
        #expect(appState.subscription == .none)
    }
}

@MainActor
struct InterpretationTests {
    private func makeViewModel(preferred: Lens = .psychology) -> (InterpretationViewModel, MockReadAloudService, InMemoryDreamStore) {
        let store = InMemoryDreamStore()
        let appState = AppState(store: InMemoryPreferencesStore())
        appState.preferredLens = preferred
        let readAloud = MockReadAloudService()
        let viewModel = InterpretationViewModel(dreamID: store.dreams[0].id, store: store, appState: appState,
                                                readAloud: readAloud, imageSaver: MockImageSaver())
        return (viewModel, readAloud, store)
    }

    @Test func preferredLensIsMainAndOthersAreAlternatives() {
        let (viewModel, _, _) = makeViewModel(preferred: .spiritual)
        #expect(viewModel.mainLens == .spiritual)
        #expect(viewModel.alternativeLenses == [.psychology, .dreamBook])
        #expect(viewModel.durationText == "1:04")
    }

    @Test func promotingALensSwapsItAndResetsPlayer() {
        let (viewModel, readAloud, _) = makeViewModel()
        viewModel.togglePlayback()
        viewModel.toggleExpanded(.dreamBook)
        #expect(readAloud.state == .playing)

        viewModel.promote(.dreamBook)

        #expect(viewModel.mainLens == .dreamBook)
        #expect(viewModel.alternativeLenses == [.psychology, .spiritual])
        #expect(viewModel.expandedLenses.isEmpty)
        #expect(readAloud.state == .idle)
    }

    @Test func playbackTogglesBetweenPlayAndPause() {
        let (viewModel, readAloud, _) = makeViewModel()
        viewModel.togglePlayback()
        #expect(readAloud.state == .playing)
        #expect(readAloud.lastText == viewModel.text(for: .psychology))
        viewModel.togglePlayback()
        #expect(readAloud.state == .paused)
    }

    @Test func notesAreSavedToTheDream() {
        let (viewModel, _, store) = makeViewModel()
        viewModel.notes = "Work deadline on Friday"
        #expect(store.dreams[0].notes == "Work deadline on Friday")
    }
}

@MainActor
struct RecordFlowTests {
    @Test func finishedAnalysisSavesTheDreamAndReportsIt() async throws {
        let store = InMemoryDreamStore(seed: [])
        var finishedID: Dream.ID?
        let flow = RecordFlowViewModel(speech: MockSpeechService(), analysisService: MockDreamAnalysisService(stepDuration: .zero),
                                       store: store, onFinish: { finishedID = $0 }, onCancel: {})

        flow.record.transcript = "A long hallway"
        await flow.finishRecording()
        flow.details?.toggle(.joy)
        flow.interpret(includeDetails: true)
        await flow.analysis?.run()
        flow.showInterpretation()

        let dream = try #require(store.dreams.first)
        #expect(dream.transcript == "A long hallway")
        #expect(dream.emotions == [.joy, .anxiety, .confusion])
        #expect(finishedID == dream.id)
    }

    @Test func analysisStepsProgressInOrder() async {
        let viewModel = AnalysisViewModel(draft: DreamDraft(), service: MockDreamAnalysisService(stepDuration: .zero),
                                          store: InMemoryDreamStore(seed: []))
        #expect(viewModel.status(of: .reading) == .active)
        #expect(viewModel.status(of: .writing) == .pending)
        await viewModel.run()
        #expect(AnalysisStep.allCases.allSatisfy { viewModel.status(of: $0) == .done })
        #expect(viewModel.isFinished)
    }
}

@MainActor
struct JournalAndLibraryTests {
    private let calendar = Calendar(identifier: .gregorian)
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 8))! }

    @Test func summaryIsComputedFromStoredDreams() {
        let store = InMemoryDreamStore(seed: MockData.seedDreams(now: now, calendar: calendar))
        let viewModel = JournalViewModel(appState: AppState(store: InMemoryPreferencesStore()), store: store,
                                         now: { now }, calendar: calendar)

        let summary = viewModel.summary
        #expect(summary.title == "Your September")
        #expect(summary.dreamCount == 12)
        #expect(summary.mostFrequentSymbol == "stairs")
        #expect(summary.distribution.first?.emotion == .anxiety)
        #expect(viewModel.sections.first?.rows.first?.dateText == "Yesterday")
    }

    @Test func homeInsightFindsTheRepeatedSymbol() {
        let store = InMemoryDreamStore(seed: MockData.seedDreams(now: now, calendar: calendar))
        let appState = AppState(store: InMemoryPreferencesStore())
        appState.userName = "Anna"
        let viewModel = HomeViewModel(appState: appState, store: store,
                                      catalog: MockSymbolCatalog(), now: { now }, calendar: calendar)

        #expect(viewModel.greeting == "Good morning, Anna")
        #expect(viewModel.insight == "Stairs appeared in 3 of your dreams this week.")
        #expect(viewModel.weekCaption == "3 dreams caught this week")
    }

    @Test func librarySearchAndCategoriesFilterTiles() {
        let viewModel = LibraryViewModel(appState: AppState(store: InMemoryPreferencesStore()), catalog: MockSymbolCatalog())
        #expect(viewModel.symbols.count == 8)

        viewModel.category = .animals
        #expect(viewModel.symbols.map(\.id) == ["snakes", "dog"])

        viewModel.query = "teeth"
        #expect(viewModel.symbols.map(\.id) == ["teeth"])
        #expect(viewModel.sectionTitle == "Results")
    }
}
