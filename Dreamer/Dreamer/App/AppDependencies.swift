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
    @ObservationIgnored let makeSpeechService: @MainActor () -> any SpeechService
    @ObservationIgnored let makeReadAloudService: @MainActor () -> any ReadAloudService

    init(dreamStore: any DreamStore,
         analysis: any DreamAnalysisService,
         purchases: any PurchaseService,
         catalog: any SymbolCatalog,
         imageSaver: any ImageSaving,
         makeSpeechService: @escaping @MainActor () -> any SpeechService,
         makeReadAloudService: @escaping @MainActor () -> any ReadAloudService) {
        self.dreamStore = dreamStore
        self.analysis = analysis
        self.purchases = purchases
        self.catalog = catalog
        self.imageSaver = imageSaver
        self.makeSpeechService = makeSpeechService
        self.makeReadAloudService = makeReadAloudService
    }

    /// Phase 1 app: mocked data, speech and purchases; real on-device read-out and photo saving.
    static func live() -> AppDependencies {
        AppDependencies(
            dreamStore: InMemoryDreamStore(),
            analysis: MockDreamAnalysisService(),
            purchases: MockPurchaseService(),
            catalog: MockSymbolCatalog(),
            imageSaver: PhotoLibraryImageSaver(),
            makeSpeechService: { MockSpeechService() },
            makeReadAloudService: { SpeechSynthesizerReadAloudService() }
        )
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
