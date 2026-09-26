import SwiftUI

extension EnvironmentValues {
    /// The app's analytics (set at the root; previews get the debug log).
    @Entry var analytics: any Analytics = NoopAnalytics()
}

extension View {
    /// Reports a screen view each time the screen appears.
    func trackScreen(_ screen: AnalyticsScreen) -> some View {
        modifier(TrackScreen(screen: screen))
    }
}

private struct TrackScreen: ViewModifier {
    let screen: AnalyticsScreen
    @Environment(\.analytics) private var analytics

    func body(content: Content) -> some View {
        content.onAppear { analytics.screen(screen) }
    }
}
