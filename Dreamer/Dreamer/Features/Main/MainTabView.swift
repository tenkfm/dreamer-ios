import SwiftUI

/// Custom tab container: one NavigationStack per tab (paths live in AppState) and a floating
/// glass tab bar that hides on pushed screens.
struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        @Bindable var appState = appState
        let tab = appState.selectedTab

        ZStack(alignment: .bottom) {
            NavigationStack(path: pathBinding(for: tab)) {
                root(for: tab)
                    .offlineBannerInset()
                    .hideSystemNavigationBar()
                    .navigationDestination(for: Route.self) { route in
                        RouteDestination(route: route)
                            .offlineBannerInset()
                            .hideSystemNavigationBar()
                    }
            }
            .id(tab)

            // Stays mounted so its entrance plays once; slides away on pushed screens.
            let isRoot = appState.path(for: tab).isEmpty
            DreamerTabBar(items: AppTab.allCases.map { ($0, $0.tabBarItem) }, selection: $appState.selectedTab)
                .padding(.bottom, DS.Size.tabBarBottom)
                .offset(y: isRoot ? 0 : 120)
                .opacity(isRoot ? 1 : 0)
                .allowsHitTesting(isRoot)
                .accessibilityHidden(!isRoot)
                .animation(.soft(0.45), value: isRoot)
                .enterUp(1.1, distance: 40)
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(isPresented: $appState.isPaywallSheetPresented) {
            PaywallSheet(viewModel: PaywallViewModel(purchases: dependencies.purchases, appState: appState,
                                                     placement: .record, analytics: dependencies.analytics) {
                appState.isPaywallSheetPresented = false
            })
        }
        .fullScreenCover(isPresented: $appState.isRecordFlowPresented) {
            ViewModelHost {
                makeRecordFlowViewModel()
            } content: { viewModel in
                RecordFlowView(viewModel: viewModel)
                    .offlineBannerInset()
            }
            .scrollEdgeEffectsHidden()
        }
    }

    @ViewBuilder private func root(for tab: AppTab) -> some View {
        switch tab {
        case .today:
            HomeView(viewModel: HomeViewModel(appState: appState, store: dependencies.dreamStore, catalog: dependencies.catalog,
                                              insights: dependencies.insights, drafts: dependencies.drafts, now: homeClock))
        case .journal:
            JournalView(viewModel: JournalViewModel(appState: appState, store: dependencies.dreamStore, images: dependencies.imageLoader,
                                                    insights: dependencies.insights, drafts: dependencies.drafts,
                                                    analytics: dependencies.analytics))
        case .library:
            LibraryView(viewModel: LibraryViewModel(appState: appState, catalog: dependencies.catalog))
        }
    }

    private func makeRecordFlowViewModel() -> RecordFlowViewModel {
        let flow = RecordFlowViewModel(dependencies: dependencies) { dreamID in
            appState.finishRecordFlow(with: dreamID)
            // Placement B of the tracking question: after the first interpretation.
            dependencies.trackingConsent.moment(.firstInterpretation)
        } onCancel: {
            appState.isRecordFlowPresented = false
        }
        if let draft = appState.draftToRead {
            appState.draftToRead = nil
            flow.read(draft)
        }
        #if DEBUG
        DebugLaunch.prepare(flow)
        #endif
        return flow
    }

    private var homeClock: () -> Date {
        #if DEBUG
        if let clock = DebugLaunch.clock { return clock }
        #endif
        return Date.init
    }

    private func pathBinding(for tab: AppTab) -> Binding<[Route]> {
        Binding(get: { appState.path(for: tab) },
                set: { appState.setPath($0, for: tab) })
    }
}

/// Builds the screen for a pushed route.
private struct RouteDestination: View {
    let route: Route

    @Environment(AppState.self) private var appState
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        switch route {
        case .settings:
            SettingsView(viewModel: SettingsViewModel(
                appState: appState, purchases: dependencies.purchases,
                account: AccountController(auth: dependencies.auth, dreamStore: dependencies.dreamStore,
                                           drafts: dependencies.drafts, appState: appState,
                                           unlink: dependencies.unlinkAccount,
                                           unregisterPush: dependencies.unregisterPush),
                analytics: dependencies.analytics))
        case .interpretation(let id):
            ViewModelHost {
                InterpretationViewModel(dreamID: id, store: dependencies.dreamStore, appState: appState,
                                        readAloud: dependencies.makeReadAloudService(), imageSaver: dependencies.imageSaver,
                                        analytics: dependencies.analytics, notesService: dependencies.api,
                                        imageLoader: dependencies.imageLoader, imageActions: dependencies.imageActions,
                                        imageGenerationEnabled: dependencies.featureFlags.isEnabled(.imageGenerationEnabled),
                                        shareCards: dependencies.shareCards, instagramAppID: dependencies.instagramAppID)
            } content: { viewModel in
                InterpretationView(viewModel: viewModel)
            }
        case .symbol(let id):
            ViewModelHost {
                SymbolDetailViewModel(slug: id, catalog: dependencies.catalog, appState: appState,
                                      analytics: dependencies.analytics)
            } content: { viewModel in
                SymbolDetailView(viewModel: viewModel)
            }
        }
    }
}

/// Creates a view model once, when the view first appears, and keeps it for the view's lifetime.
/// Use for view models that own resources (speech, audio) so they are not rebuilt on every parent update.
struct ViewModelHost<ViewModel: AnyObject, Content: View>: View {
    let make: () -> ViewModel
    @ViewBuilder let content: (ViewModel) -> Content

    @State private var viewModel: ViewModel?

    var body: some View {
        if let viewModel {
            content(viewModel)
        } else {
            DS.Palette.background
                .ignoresSafeArea()
                .onAppear { viewModel = make() }
        }
    }
}

#Preview {
    MainTabView()
        .environment(AppDependencies.preview())
        .environment(ReminderController.preview)
        .environment(AppLock(appState: .preview(), authenticator: MockAuthenticator()))
        .environment(AppState.preview())
}
