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
                    .hideSystemNavigationBar()
                    .navigationDestination(for: Route.self) { route in
                        RouteDestination(route: route)
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
        .fullScreenCover(isPresented: $appState.isRecordFlowPresented) {
            ViewModelHost {
                makeRecordFlowViewModel()
            } content: { viewModel in
                RecordFlowView(viewModel: viewModel)
            }
            .scrollEdgeEffectsHidden()
        }
    }

    @ViewBuilder private func root(for tab: AppTab) -> some View {
        switch tab {
        case .today:
            HomeView(viewModel: HomeViewModel(appState: appState, store: dependencies.dreamStore, catalog: dependencies.catalog))
        case .journal:
            JournalView(viewModel: JournalViewModel(appState: appState, store: dependencies.dreamStore))
        case .library:
            LibraryView(viewModel: LibraryViewModel(appState: appState, catalog: dependencies.catalog))
        }
    }

    private func makeRecordFlowViewModel() -> RecordFlowViewModel {
        let flow = RecordFlowViewModel(dependencies: dependencies) { dreamID in
            appState.finishRecordFlow(with: dreamID)
        } onCancel: {
            appState.isRecordFlowPresented = false
        }
        #if DEBUG
        DebugLaunch.prepare(flow)
        #endif
        return flow
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
            SettingsView(viewModel: SettingsViewModel(appState: appState, purchases: dependencies.purchases, store: dependencies.dreamStore))
        case .interpretation(let id):
            ViewModelHost {
                InterpretationViewModel(dreamID: id, store: dependencies.dreamStore, appState: appState,
                                        readAloud: dependencies.makeReadAloudService(), imageSaver: dependencies.imageSaver)
            } content: { viewModel in
                InterpretationView(viewModel: viewModel)
            }
        case .symbol(let id):
            if let symbol = dependencies.catalog.symbol(id: id) {
                SymbolDetailView(symbol: symbol)
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
        .environment(AppState.preview())
}
