import SwiftUI

/// Content is at least as tall as the screen (so Spacers distribute it like the design),
/// and scrolls when it does not fit (iPhone SE, large Dynamic Type).
struct FillingScrollView<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                content()
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
    }
}

/// Types `text` in character by character (≈ 40 ms/char) with a blinking caret.
struct TypewriterText: View {
    var text: String
    var startDelay: Double = 0
    var interval: Duration = .milliseconds(40)
    var style: TextStyle = .body

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.entranceActive) private var entranceActive
    @State private var visibleCount = 0

    var body: some View {
        // The hidden full text reserves the final size so the container does not grow while typing.
        ZStack(alignment: .top) {
            Text(verbatim: text + "|").textStyle(style).hidden()
            CaretText(text: String(text.prefix(visibleCount)), style: style)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .task(id: entranceActive) {
            guard entranceActive, visibleCount == 0 else { return }
            guard !reduceMotion else { visibleCount = text.count; return }
            try? await Task.sleep(for: .seconds(startDelay))
            while visibleCount < text.count, !Task.isCancelled {
                try? await Task.sleep(for: interval)
                visibleCount += 1
            }
        }
    }
}
