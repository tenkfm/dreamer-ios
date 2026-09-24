import SwiftUI

// Presentation of model values: colors, icons and images live in the design system,
// so the model layer stays free of SwiftUI.

extension Emotion {
    var color: Color {
        switch self {
        case .anxiety: DS.Emotion.anxiety
        case .confusion: DS.Emotion.confusion
        case .calm: DS.Emotion.calm
        case .joy: DS.Emotion.joy
        case .fear: DS.Emotion.fear
        }
    }
}

extension AppTab {
    var tabBarItem: TabBarItem {
        switch self {
        case .today: TabBarItem(id: rawValue, title: "Today", systemImage: "house")
        case .journal: TabBarItem(id: rawValue, title: "Journal", systemImage: "book.closed")
        case .library: TabBarItem(id: rawValue, title: "Library", systemImage: "square.grid.2x2")
        }
    }
}

/// Resolves stored image names (asset names in phase 1) to images, with the sky as placeholder.
enum DreamImage {
    static let placeholderName = Dream.placeholderImageName

    static func image(named name: String?) -> Image {
        Image(name ?? placeholderName)
    }

    #if canImport(UIKit)
    static func uiImage(named name: String?) -> UIImage? {
        UIImage(named: name ?? placeholderName)
    }
    #endif
}
