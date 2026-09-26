import SwiftUI

/// Switches between onboarding, the hard paywall and the main app.
struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(ReminderController.self) private var reminders
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            switch appState.rootScreen {
            case .onboarding:
                OnboardingFlowView(viewModel: OnboardingViewModel(appState: appState, step: initialOnboardingStep,
                                                                  analytics: dependencies.analytics))
                    .offlineBannerInset()
                    .transition(.opacity)
            case .paywall:
                ZStack {
                    SkyBackground(kind: .full)
                    PaywallView(viewModel: PaywallViewModel(purchases: dependencies.purchases, appState: appState,
                                                            placement: .gate, analytics: dependencies.analytics))
                        .offlineBannerInset()
                }
                .transition(.opacity)
            case .main:
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.soft(0.6), value: appState.rootScreen)
        // The app always sets its own appearance: night mode, never the system setting.
        .preferredColorScheme(appState.isNightMode ? .dark : .light)
        // Screens draw clear sky under their headers; no iOS 26 blur at scroll edges anywhere.
        .scrollEdgeEffectsHidden()
        .onChange(of: NotificationRouter.shared.pending, initial: true) {
            // A tapped reminder or push (cold starts included).
            guard let tap = NotificationRouter.shared.consume() else { return }
            if let pushType = tap.pushType { dependencies.analytics.track(.pushOpened(type: pushType)) }
            appState.handle(tap.link)
        }
        .task(id: ReminderTrigger(settings: appState.reminders, userID: appState.userID,
                                  dreams: dependencies.dreamStore.summaries.count, trialEndsAt: appState.trialEndsAt,
                                  active: scenePhase == .active)) {
            // Replanned on every change that affects the reminders, and on each return to the app.
            guard scenePhase == .active else { return }
            await reminders.reschedule()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            // The reminder follows the local 7:30 after travel.
            Task { await reminders.reschedule() }
        }
        .overlay {
            if reminders.isPrePromptPresented && !dependencies.trackingConsent.isPrePromptPresented {
                ReminderPrePrompt(minutes: appState.reminders.reminderMinutes,
                                  onEnable: { Task { await reminders.enable() } },
                                  onDecline: reminders.decline)
                    .transition(.opacity.combined(with: .offset(y: 18)))
            }
        }
        .animation(.soft(0.5), value: reminders.isPrePromptPresented)
        .task {
            // Install attribution and the ad networks start with the tracking answer (at once when
            // the user answered before; otherwise after the question).
            await dependencies.trackingConsent.launched()
        }
        .overlay {
            if dependencies.trackingConsent.isPrePromptPresented {
                TrackingPrePrompt { Task { await dependencies.trackingConsent.continueToSystemPrompt() } }
                    .transition(.opacity.combined(with: .offset(y: 18)))
            }
        }
        .animation(.soft(0.5), value: dependencies.trackingConsent.isPrePromptPresented)
        .task {
            // Lets the 9 PM / 5 AM schedule switch while the app stays open.
            while !Task.isCancelled {
                appState.refreshClock()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        // Universal links arrive here at a cold start and while the app runs.
        .onOpenURL { url in
            if let link = DeepLink(url: url, apiHost: AppConfig.current.apiBaseURL?.host()) {
                appState.handle(link)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { appState.refreshClock() }
        }
        .task(id: AnalyticsContext(preferredLens: appState.preferredLens, paywallVariant: appState.paywallVariant)) {
            // Every later event carries the lens and the paywall variant.
            dependencies.analytics.setContext(AnalyticsContext(preferredLens: appState.preferredLens,
                                                               paywallVariant: appState.paywallVariant))
        }
        .task(id: appState.userID) {
            // Every sign-in (and a session restored at launch) links the account in the SDKs.
            if let userID = appState.userID { await dependencies.linkAccount(userID: userID) }
        }
        .task(id: appState.userID) {
            // Store access for the whole session: renewals, expiries and refunds apply at once.
            guard appState.isSignedIn else { return }
            appState.requestSubscriptionRefresh(afterPurchase: false)
            await subscriptionSync.followEntitlements()
        }
        .task(id: appState.subscriptionRefresh) {
            guard let request = appState.subscriptionRefresh, appState.isSignedIn else { return }
            await subscriptionSync.refreshBackend(expectPremium: request.afterPurchase)
        }
        .task(id: DraftFlushTrigger(online: dependencies.network.isOnline, userID: appState.userID, phase: scenePhase)) {
            // Told dreams waiting for the backend go out when there is a connection and an account.
            guard dependencies.network.isOnline, appState.isSignedIn, scenePhase == .active else { return }
            await dependencies.drafts?.flush()
        }
        .task(id: appState.profileWriteRequest) {
            // A setting changed (the main lens...): up to /v1/me; offline it waits for the next launch.
            guard appState.profileWriteRequest != nil else { return }
            await ProfileSync(appState: appState, profiles: dependencies.profiles).sendPending()
        }
        .task(id: appState.pendingProfileSync) {
            // New account: quiz answers and settings go up; existing one: the server's profile comes down.
            guard let direction = appState.pendingProfileSync else { return }
            await ProfileSync(appState: appState, profiles: dependencies.profiles).run(direction)
        }
        .task {
            // The backend ended the session (refresh refused): back to sign-in.
            guard let tokens = dependencies.tokens else { return }
            for await _ in tokens.signedOutEvents {
                appState.signedOut()
                await dependencies.unlinkAccount()
            }
        }
    }

    private var subscriptionSync: SubscriptionSync {
        SubscriptionSync(appState: appState, purchases: dependencies.purchases, backend: dependencies.subscriptionStatus)
    }

    private var initialOnboardingStep: OnboardingViewModel.Step {
        #if DEBUG
        DebugLaunch.onboardingStep ?? .welcome
        #else
        .welcome
        #endif
    }
}

#Preview {
    RootView()
        .environment(AppDependencies.preview())
        .environment(ReminderController.preview)
        .environment(AppState.preview(onboardingCompleted: false))
}

/// Re-runs the draft flush when the connection, the account or the foreground state changes.
private struct DraftFlushTrigger: Equatable {
    var online: Bool
    var userID: String?
    var phase: ScenePhase
}

/// What the pending reminders depend on; a change replans them.
private struct ReminderTrigger: Equatable {
    var settings: ReminderSettings
    var userID: String?
    var dreams: Int
    var trialEndsAt: Date?
    var active: Bool
}
