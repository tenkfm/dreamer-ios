import SwiftUI

/// Shows the offline banner above a screen's content. Applied inside every navigation container:
/// NavigationStack does not pass an outer safe-area inset down to its screens.
struct OfflineBannerInset: ViewModifier {
    @Environment(AppDependencies.self) private var dependencies

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if !dependencies.network.isOnline {
                    OfflineBanner()
                        .padding(.top, 4)
                        .padding(.bottom, 2)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.soft(0.4), value: dependencies.network.isOnline)
    }
}

extension View {
    func offlineBannerInset() -> some View {
        modifier(OfflineBannerInset())
    }
}
