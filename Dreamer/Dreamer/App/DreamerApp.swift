import SwiftUI

@main
struct DreamerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var dependencies: AppDependencies
    @State private var appState: AppState
    @State private var reminders: ReminderController
    @State private var appLock: AppLock

    init() {
        let dependencies = AppDependencies.live()
        var appState = AppState(store: UserDefaultsPreferencesStore())
        #if DEBUG
        // UI tests start every launch as a fresh install.
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") { appState = AppState(store: InMemoryPreferencesStore()) }
        #endif
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
        _reminders = State(initialValue: ReminderController(scheduler: dependencies.notificationScheduler,
                                                            appState: appState, store: dependencies.dreamStore))
        _appLock = State(initialValue: AppLock(appState: appState, authenticator: dependencies.authenticator))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(dependencies)
                .environment(appState)
                .environment(reminders)
                .environment(appLock)
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        }
    }
}
