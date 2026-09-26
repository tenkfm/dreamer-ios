import SwiftUI

@main
struct DreamerApp: App {
    @State private var dependencies: AppDependencies
    @State private var appState: AppState

    init() {
        let dependencies = AppDependencies.live()
        var appState = AppState(store: UserDefaultsPreferencesStore())
        var debugState: AppState?
        #if DEBUG
        debugState = DebugLaunch.makeAppState(dependencies: dependencies)
        #endif
        if let debugState {
            appState = debugState
        } else if case .some(let stored) = AppDependencies.storedUserID(mode: dependencies.mode) {
            appState.reconcileSession(storedUserID: stored)
            // Settings may have changed on another device since the last launch.
            appState.requestProfilePull()
        }
        _dependencies = State(initialValue: dependencies)
        _appState = State(initialValue: appState)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(dependencies)
                .environment(\.analytics, dependencies.analytics)
                .environment(appState)
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        }
    }
}
