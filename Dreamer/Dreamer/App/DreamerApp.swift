import SwiftUI

@main
struct DreamerApp: App {
    @State private var dependencies: AppDependencies
    @State private var appState: AppState

    init() {
        let dependencies = AppDependencies.live()
        var appState = AppState(store: UserDefaultsPreferencesStore())
        #if DEBUG
        if let debugState = DebugLaunch.makeAppState(dependencies: dependencies) { appState = debugState }
        #endif
        _dependencies = State(initialValue: dependencies)
        _appState = State(initialValue: appState)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(dependencies)
                .environment(appState)
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        }
    }
}
