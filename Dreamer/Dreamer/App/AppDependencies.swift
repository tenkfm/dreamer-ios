import Foundation
import Observation

/// Composition root. Owns the service implementations and is injected through the environment.
/// `live()` picks the backend (API) or the local mocks once per launch; views never know which.
@MainActor
@Observable
final class AppDependencies {
    enum Mode: String, Sendable {
        /// Everything local (previews, tests, `-mockServices`, builds without an API host).
        case mock
        /// The backend of the build's environment.
        case live
    }

    let mode: Mode
    /// Nil in mock mode.
    let api: APIClient?
    /// Nil in mock mode.
    let tokens: TokenManager?
    let auth: any AuthService
    let analytics: any Analytics
    let dreamStore: any DreamStore
    let analysis: any DreamAnalysisService
    let purchases: any PurchaseService
    let catalog: any SymbolCatalog
    let imageSaver: any ImageSaving
    /// Remote switches for this session (see FeatureFlags).
    let featureFlags: FeatureFlags
    let crashReporter: any CrashReporter
    let network: NetworkMonitor
    @ObservationIgnored let makeSpeechService: @MainActor () -> any SpeechService
    @ObservationIgnored let makeReadAloudService: @MainActor () -> any ReadAloudService

    init(mode: Mode = .mock,
         api: APIClient? = nil,
         tokens: TokenManager? = nil,
         auth: any AuthService = MockAuthService(),
         analytics: any Analytics = NoopAnalytics(),
         dreamStore: any DreamStore,
         analysis: any DreamAnalysisService,
         purchases: any PurchaseService,
         catalog: any SymbolCatalog,
         imageSaver: any ImageSaving,
         featureFlags: FeatureFlags = .defaults,
         crashReporter: any CrashReporter = NoopCrashReporter(),
         network: NetworkMonitor = NetworkMonitor(isOnline: true),
         makeSpeechService: @escaping @MainActor () -> any SpeechService,
         makeReadAloudService: @escaping @MainActor () -> any ReadAloudService) {
        self.mode = mode
        self.api = api
        self.tokens = tokens
        self.auth = auth
        self.analytics = analytics
        self.dreamStore = dreamStore
        self.analysis = analysis
        self.purchases = purchases
        self.catalog = catalog
        self.imageSaver = imageSaver
        self.featureFlags = featureFlags
        self.crashReporter = crashReporter
        self.network = network
        self.makeSpeechService = makeSpeechService
        self.makeReadAloudService = makeReadAloudService
    }

    /// The app's services. Live mode talks to the build's backend; services whose live version
    /// belongs to a later story (speech IOS-04, journal IOS-06, purchases IOS-03, voice IOS-05.5)
    /// stay local until then.
    static func live(config: AppConfig = .current, arguments: [String] = ProcessInfo.processInfo.arguments) -> AppDependencies {
        // First, so a crash anywhere later in the launch is still reported.
        let crashReporter = CrashReporting.makeReporter(config: config)
        let featureFlags = liveFeatureFlags()
        let network = liveNetworkMonitor()

        guard mode(config: config, arguments: arguments) == .live, let baseURL = config.apiBaseURL else {
            return AppDependencies(
                mode: .mock,
                dreamStore: InMemoryDreamStore(),
                analysis: MockDreamAnalysisService(),
                purchases: MockPurchaseService(),
                catalog: MockSymbolCatalog(),
                imageSaver: PhotoLibraryImageSaver(),
                featureFlags: featureFlags,
                crashReporter: crashReporter,
                network: network,
                makeSpeechService: { MockSpeechService() },
                makeReadAloudService: { SpeechSynthesizerReadAloudService() }
            )
        }

        // Refresh goes through a client without tokens: it must not wait for itself.
        let publicClient = APIClient(baseURL: baseURL, tokens: nil)
        let tokens = TokenManager(store: KeychainStore()) { refreshToken throws(APIError) in
            try await publicClient.refreshTokens(refreshToken: refreshToken)
        }
        let api = APIClient(baseURL: baseURL, tokens: tokens)
        return AppDependencies(
            mode: .live,
            api: api,
            tokens: tokens,
            auth: APIAuthService(client: api, tokens: tokens),
            dreamStore: InMemoryDreamStore(),
            analysis: APIDreamAnalysisService(client: api),
            purchases: MockPurchaseService(),
            catalog: MockSymbolCatalog(),
            imageSaver: PhotoLibraryImageSaver(),
            featureFlags: featureFlags,
            crashReporter: crashReporter,
            network: network,
            makeSpeechService: { MockSpeechService() },
            makeReadAloudService: { SpeechSynthesizerReadAloudService() }
        )
    }

    /// Mock mode for `-mockServices` (Debug and Staging builds, UI tests and demos) and for builds
    /// without an API host (Release until the production domain exists). `-debugScreen` implies
    /// mock data too, so screenshots are deterministic; add `-liveServices` to override.
    nonisolated static func mode(config: AppConfig, arguments: [String]) -> Mode {
        guard config.apiBaseURL != nil else { return .mock }
        #if DEBUG || STAGING
        if arguments.contains("-liveServices") { return .live }
        if arguments.contains("-mockServices") || arguments.contains("-debugScreen") { return .mock }
        #endif
        return .live
    }

    private static func liveNetworkMonitor() -> NetworkMonitor {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-offline") { return NetworkMonitor(isOnline: false) }
        #endif
        return NetworkMonitor()
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

extension AppDependencies {
    /// The signed-in user id stored with the tokens (Keychain), read at launch. In mock mode the
    /// session lives in the preferences only.
    nonisolated static func storedUserID(mode: Mode, store: any SecureStore = KeychainStore()) -> String?? {
        guard mode == .live else { return .none }
        return .some(TokenManager.storedSession(in: store)?.userID)
    }
}

extension AppState {
    static func preview(onboardingCompleted: Bool = true) -> AppState {
        let state = AppState(store: InMemoryPreferencesStore())
        if onboardingCompleted {
            state.signedIn(userID: "preview-user", isNewUser: false)
            state.activateSubscription(.yearly)
        }
        return state
    }
}
