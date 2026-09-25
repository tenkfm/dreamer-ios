import Foundation
import Observation

/// Composition root. Owns the service implementations and is injected through the environment.
@MainActor
@Observable
final class AppDependencies {
    let dreamStore: any DreamStore
    let analysis: any DreamAnalysisService
    let purchases: any PurchaseService
    let catalog: any SymbolCatalog
    let imageSaver: any ImageSaving
    /// Remote switches for this session (see FeatureFlags).
    let featureFlags: FeatureFlags
    let crashReporter: any CrashReporter
    @ObservationIgnored let makeSpeechService: @MainActor () -> any SpeechService
    @ObservationIgnored let makeReadAloudService: @MainActor () -> any ReadAloudService

    init(dreamStore: any DreamStore,
         analysis: any DreamAnalysisService,
         purchases: any PurchaseService,
         catalog: any SymbolCatalog,
         imageSaver: any ImageSaving,
         featureFlags: FeatureFlags = .defaults,
         crashReporter: any CrashReporter = NoopCrashReporter(),
         makeSpeechService: @escaping @MainActor () -> any SpeechService,
         makeReadAloudService: @escaping @MainActor () -> any ReadAloudService) {
        self.dreamStore = dreamStore
        self.analysis = analysis
        self.purchases = purchases
        self.catalog = catalog
        self.imageSaver = imageSaver
        self.featureFlags = featureFlags
        self.crashReporter = crashReporter
        self.makeSpeechService = makeSpeechService
        self.makeReadAloudService = makeReadAloudService
    }

    /// Phase 1 app: mocked data, speech and purchases; real on-device read-out and photo saving.
    static func live() -> AppDependencies {
        // First, so a crash anywhere later in the launch is still reported.
        let crashReporter = CrashReporting.makeReporter(config: .current)
        return AppDependencies(
            dreamStore: InMemoryDreamStore(),
            analysis: MockDreamAnalysisService(),
            purchases: MockPurchaseService(),
            catalog: MockSymbolCatalog(),
            imageSaver: PhotoLibraryImageSaver(),
            featureFlags: liveFeatureFlags(),
            crashReporter: crashReporter,
            makeSpeechService: { MockSpeechService() },
            makeReadAloudService: { SpeechSynthesizerReadAloudService() }
        )
    }

    private static func liveFeatureFlags() -> FeatureFlags {
        let flags = PostHogFeatureFlagService(config: .current).flags
        #if DEBUG
        return flags.overridden(by: ProcessInfo.processInfo.arguments)
        #else
        return flags
        #endif
    }

    static func preview() -> AppDependencies {
        AppDependencies(
            dreamStore: InMemoryDreamStore(),
            analysis: MockDreamAnalysisService(),
            purchases: MockPurchaseService(),
            catalog: MockSymbolCatalog(),
            imageSaver: MockImageSaver(),
            makeSpeechService: { MockSpeechService() },
            makeReadAloudService: { MockReadAloudService() }
        )
    }
}

extension AppState {
    static func preview(onboardingCompleted: Bool = true) -> AppState {
        let state = AppState(store: InMemoryPreferencesStore())
        if onboardingCompleted { state.activateSubscription(.yearly) }
        return state
    }
}
