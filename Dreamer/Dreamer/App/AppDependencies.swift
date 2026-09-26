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
    let profiles: any ProfileService
    let subscriptionStatus: any SubscriptionStatusService
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
    /// Told dreams waiting for the backend (nil when the local store cannot open).
    let drafts: DraftQueue?
    /// Server speech-to-text for recordings the device gave no text for (nil: flag off, mock mode).
    let transcriber: (any RecordingTranscriber)?
    /// Dream images from the backend (nil in mock mode: the asset catalog).
    let imageLoader: (any DreamImageLoading)?
    let imageActions: (any DreamImageActions)?
    /// The backend's 9:16 share card (nil in mock mode: the dream image is shared).
    let shareCards: (any ShareCardProviding)?
    /// The backend's week, morning and month insights (nil in mock mode: computed from the dreams).
    let insights: InsightStore?
    /// Install attribution (the MMP); a no-op until it is chosen.
    let attribution: any AttributionService
    /// Ad networks' SDKs (Meta, TikTok); none until their app ids exist.
    let adNetworks: [any AdNetworkSDK]
    /// The tracking question and the start of install measurement with its answer.
    let trackingConsent: TrackingConsent
    /// Local notifications (the morning reminder, the trial reminder).
    @ObservationIgnored let notificationScheduler: any NotificationScheduling
    /// This install's push token on the backend (nil registry in mock mode).
    @ObservationIgnored let pushDevices: PushDevices
    /// Face ID / passcode for the journal lock.
    @ObservationIgnored let authenticator: any DeviceAuthenticator
    let instagramAppID: String?
    @ObservationIgnored let makeSpeechService: @MainActor () -> any SpeechService
    @ObservationIgnored let makeReadAloudService: @MainActor () -> any ReadAloudService
    @ObservationIgnored let makeSpeechPermissions: @MainActor () -> any SpeechPermissions

    init(mode: Mode = .mock,
         api: APIClient? = nil,
         tokens: TokenManager? = nil,
         auth: any AuthService = MockAuthService(),
         profiles: any ProfileService = MockProfileService(),
         subscriptionStatus: any SubscriptionStatusService = MockSubscriptionStatusService(),
         analytics: any Analytics = NoopAnalytics(),
         dreamStore: any DreamStore,
         analysis: any DreamAnalysisService,
         purchases: any PurchaseService,
         catalog: any SymbolCatalog,
         imageSaver: any ImageSaving,
         featureFlags: FeatureFlags = .defaults,
         crashReporter: any CrashReporter = NoopCrashReporter(),
         network: NetworkMonitor = NetworkMonitor(isOnline: true),
         drafts: DraftQueue? = nil,
         transcriber: (any RecordingTranscriber)? = nil,
         imageLoader: (any DreamImageLoading)? = nil,
         imageActions: (any DreamImageActions)? = nil,
         shareCards: (any ShareCardProviding)? = nil,
         insights: InsightStore? = nil,
         attribution: any AttributionService = NoopAttribution(),
         adNetworks: [any AdNetworkSDK] = [],
         instagramAppID: String? = nil,
         makeSpeechService: @escaping @MainActor () -> any SpeechService,
         makeReadAloudService: @escaping @MainActor () -> any ReadAloudService,
         makeSpeechPermissions: @escaping @MainActor () -> any SpeechPermissions = { mockSpeechPermissions() },
         trackingPermission: any TrackingPermission = mockTrackingPermission(),
         notificationScheduler: any NotificationScheduling = MockNotificationScheduler(),
         authenticator: any DeviceAuthenticator = MockAuthenticator()) {
        self.authenticator = authenticator
        self.notificationScheduler = notificationScheduler
        pushDevices = PushDevices(registry: api, environment: AppConfig.current.pushEnvironment)
        self.mode = mode
        self.api = api
        self.tokens = tokens
        self.auth = auth
        self.profiles = profiles
        self.subscriptionStatus = subscriptionStatus
        self.analytics = analytics
        self.dreamStore = dreamStore
        self.analysis = analysis
        self.purchases = purchases
        self.catalog = catalog
        self.imageSaver = imageSaver
        self.featureFlags = featureFlags
        self.crashReporter = crashReporter
        self.network = network
        self.drafts = drafts
        self.transcriber = transcriber
        self.imageLoader = imageLoader
        self.imageActions = imageActions
        self.shareCards = shareCards
        self.insights = insights
        self.attribution = attribution
        self.adNetworks = adNetworks
        trackingConsent = TrackingConsent(permission: trackingPermission, analytics: analytics,
                                          measurement: MeasurementStack(attribution: attribution, adNetworks: adNetworks),
                                          askAfterFirstDream: featureFlags.isEnabled(.attAfterFirstDream))
        self.instagramAppID = instagramAppID
        self.makeSpeechService = makeSpeechService
        self.makeReadAloudService = makeReadAloudService
        self.makeSpeechPermissions = makeSpeechPermissions
    }

    /// The app's services. Live mode talks to the build's backend; services whose live version
    /// belongs to a later story (speech IOS-04, journal IOS-06, purchases IOS-03, voice IOS-05.5)
    /// stay local until then.
    static func live(config: AppConfig = .current, arguments: [String] = ProcessInfo.processInfo.arguments) -> AppDependencies {
        // First, so a crash anywhere later in the launch is still reported.
        let crashReporter = CrashReporting.makeReporter(config: config)
        let featureFlags = liveFeatureFlags()
        let network = liveNetworkMonitor()
        // A recording left by a crash or a kill mid-flow is never uploaded later.
        RecordingFiles.purge()

        let container = try? LocalStore.makeContainer()

        guard mode(config: config, arguments: arguments) == .live, let baseURL = config.apiBaseURL else {
            let dreamStore = InMemoryDreamStore()
            let images = mockImages(store: dreamStore)
            return AppDependencies(
                mode: .mock,
                dreamStore: dreamStore,
                analysis: MockDreamAnalysisService(),
                purchases: MockPurchaseService(),
                catalog: MockSymbolCatalog(),
                imageSaver: PhotoLibraryImageSaver(),
                featureFlags: featureFlags,
                crashReporter: crashReporter,
                network: network,
                drafts: container.map { DraftQueue(container: $0, submitter: MockDreamSubmitter(), store: dreamStore) },
                transcriber: mockTranscriber(),
                imageLoader: images,
                imageActions: images,
                instagramAppID: config.facebookAppID,
                makeSpeechService: { MockSpeechService(liveText: mockTranscriber() == nil) },
                makeReadAloudService: { SpeechSynthesizerReadAloudService() },
                notificationScheduler: SystemNotificationScheduler(),
                authenticator: SystemAuthenticator()
            )
        }

        // Refresh goes through a client without tokens: it must not wait for itself.
        // API failures that point to a bug or an outage become non-fatal reports (grouped by code).
        let reporting = ErrorReportingMiddleware(reporter: crashReporter)
        let publicClient = APIClient(baseURL: baseURL, tokens: nil, extraMiddlewares: [reporting], reporter: crashReporter)
        let tokens = TokenManager(store: KeychainStore()) { refreshToken throws(APIError) in
            try await publicClient.refreshTokens(refreshToken: refreshToken)
        }
        // App Attest: its own client registers keys, so the attested client never waits on itself.
        let attestor = AppAttestor(service: SystemAppAttestService(),
                                   backend: APIClient(baseURL: baseURL, tokens: tokens, extraMiddlewares: [reporting],
                                                      reporter: crashReporter),
                                   store: KeychainStore(),
                                   enforced: featureFlags.isEnabled(.attestationEnforced))
        let attestation = AttestationMiddleware(attestor: attestor, userID: { await tokens.userID })
        let api = APIClient(baseURL: baseURL, tokens: tokens, extraMiddlewares: [reporting], innerMiddlewares: [attestation],
                            reporter: crashReporter)
        // The journal is cached next to the drafts; without the local store it lives in memory.
        let dreamStore: any DreamStore = container.map { CachedDreamStore(container: $0, remote: api) }
            ?? InMemoryDreamStore(seed: [])
        let serverSpeech = featureFlags.isEnabled(.serverSttFallback)
        let ttsEnabled = featureFlags.isEnabled(.ttsEnabled)
        // Events go to PostHog when the build has its key (the debug log otherwise).
        let analytics = AnalyticsFactory.make(config: config)
        return AppDependencies(
            mode: .live,
            api: api,
            tokens: tokens,
            auth: APIAuthService(client: api, tokens: tokens),
            profiles: APIProfileService(client: api),
            subscriptionStatus: APISubscriptionStatusService(client: api),
            analytics: analytics,
            dreamStore: dreamStore,
            analysis: APIDreamAnalysisService(client: api),
            purchases: livePurchases(config: config),
            catalog: APISymbolCatalog(remote: api),
            imageSaver: PhotoLibraryImageSaver(),
            featureFlags: featureFlags,
            crashReporter: crashReporter,
            network: network,
            drafts: container.map { DraftQueue(container: $0, submitter: api, store: dreamStore) },
            transcriber: serverSpeech ? APIRecordingTranscriber(client: api) : nil,
            imageLoader: RemoteDreamImageLoader(actions: api),
            imageActions: api,
            shareCards: APIShareCardProvider(client: api),
            insights: InsightStore(service: api),
            instagramAppID: config.facebookAppID,
            makeSpeechService: { OnDeviceSpeechService(keepsAudio: serverSpeech) },
            makeReadAloudService: {
                BackendReadAloudService(source: api, fallback: SpeechSynthesizerReadAloudService(), playback: AVVoicePlayback(),
                                        analytics: analytics, ttsEnabled: ttsEnabled)
            },
            makeSpeechPermissions: { SystemSpeechPermissions() },
            trackingPermission: SystemTrackingPermission(),
            notificationScheduler: SystemNotificationScheduler(),
            authenticator: SystemAuthenticator()
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

    /// RevenueCat with a key (every real build); StoreKit 2 on the local configuration otherwise, so
    /// purchases can be tried in the simulator before the RevenueCat project exists.
    private static func livePurchases(config: AppConfig) -> any PurchaseService {
        if let key = config.revenueCatAPIKey {
            return RevenueCatPurchaseService(apiKey: key, debugLogs: config.environment != .production)
        }
        return StoreKitPurchaseService()
    }

    /// Mock mode grants the microphone; Debug builds can show the other states with
    /// `-micPermission notDetermined|denied|restricted`.
    static func mockSpeechPermissions() -> any SpeechPermissions {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-micPermission"), index + 1 < arguments.count {
            let state: SpeechPermission = switch arguments[index + 1] {
            case "notDetermined": .notDetermined
            case "denied": .denied
            case "restricted": .restricted
            default: .granted
            }
            return MockSpeechPermissions(current: state, answer: state == .notDetermined ? .granted : state)
        }
        #endif
        return MockSpeechPermissions()
    }

    /// Debug `-noLiveText`: the recording gets no live text and the mock server writes it down,
    /// to see the IOS-04.5 fallback without an unsupported language.
    private static func mockTranscriber() -> (any RecordingTranscriber)? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-noLiveText") { return MockRecordingTranscriber() }
        #endif
        return nil
    }

    /// Debug `-imagePending`: the first dream's image is "painted" in a few seconds, to see the
    /// generating state and the reveal without the backend.
    private static func mockImages(store: InMemoryDreamStore) -> MockDreamImageService? {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-imagePending"), var dream = store.dreams.first else { return nil }
        dream.image = DreamImageInfo(status: .pending, version: 1)
        store.save(dream)
        return MockDreamImageService(dream: dream)
        #else
        return nil
        #endif
    }

    /// Mock mode answered "no" long ago, so the question never interrupts; Debug builds can show it
    /// with `-askTracking`.
    static func mockTrackingPermission() -> any TrackingPermission {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-askTracking") { return MockTrackingPermission() }
        #endif
        return MockTrackingPermission(status: .denied)
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
    /// Tells every identity-aware SDK who the user is: RevenueCat (the subscription follows the
    /// account), analytics and crash reports (the same id the backend uses; never an email).
    func linkAccount(userID: String) async {
        await purchases.logIn(userID: userID)
        attribution.setUserID(userID)
        if let id = await attribution.attributionID() { purchases.setAttribution(id) }
        analytics.identify(userID: userID)
        crashReporter.setUserID(userID)
    }

    /// After sign-out, account deletion or a revoked session.
    /// Everything that measures installs, started with the tracking answer.
    var measurement: MeasurementStack {
        MeasurementStack(attribution: attribution, adNetworks: adNetworks)
    }

    /// Sign-out: remove the push token while the session can still do it.
    func unregisterPush() async {
        await pushDevices.unregister(token: PushRegistration.shared.token)
    }

    func unlinkAccount() async {
        await imageLoader?.removeAll()
        insights?.clear()
        attribution.setUserID(nil)
        await purchases.logOut()
        analytics.reset()
        crashReporter.setUserID(nil)
    }

    /// The signed-in user id stored with the tokens (Keychain), read at launch. In mock mode the
    /// session lives in the preferences only.
    nonisolated static func storedUserID(mode: Mode, store: any SecureStore = KeychainStore()) -> String?? {
        guard mode == .live else { return .none }
        return .some(TokenManager.storedSession(in: store)?.userID)
    }
}

extension AppState {
    static func preview(onboardingCompleted: Bool = true) -> AppState {
        var preferences = UserPreferences()
        preferences.userName = "Anna"
        let state = AppState(store: InMemoryPreferencesStore(preferences))
        if onboardingCompleted {
            state.signedIn(userID: "preview-user", isNewUser: false)
            state.activateSubscription(.yearly)
        }
        return state
    }
}
