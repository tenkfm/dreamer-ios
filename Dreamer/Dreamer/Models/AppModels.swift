import Foundation

enum Plan: String, CaseIterable, Codable, Sendable, Identifiable {
    case yearly, weekly

    var id: Self { self }

    /// StoreKit product ids (phase 2, placeholders).
    var productID: String {
        switch self {
        case .yearly: "dreamer.yearly"
        case .weekly: "dreamer.weekly"
        }
    }

    var title: String {
        switch self {
        case .yearly: String(localized: "Yearly")
        case .weekly: String(localized: "Weekly")
        }
    }
}

enum SubscriptionStatus: Codable, Hashable, Sendable {
    case none
    case active(Plan)

    var plan: Plan? {
        if case .active(let plan) = self { return plan }
        return nil
    }
}

/// Settings screen preferences.
struct ReminderSettings: Codable, Hashable, Sendable {
    var morningReminder = true
    /// Minutes after midnight.
    var reminderMinutes = 7 * 60 + 30
    var nightModeAfter9 = true
    var lockWithFaceID = false
}

/// Library categories (chips).
enum SymbolCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case popular, love, fear, animals, places, people

    var id: Self { self }
    var title: String { rawValue.capitalized }
}

/// A dream symbol in the Library.
struct LibrarySymbol: Identifiable, Hashable, Sendable, Codable {
    /// The backend slug (`teeth-falling-out`).
    let id: String
    var title: String
    var meaning: String
    var detail: String
    var categories: Set<SymbolCategory>
    /// Asset name used by the mock catalog.
    var imageName: String
    var glyph: Glyph
    /// Image from the backend; wins over `imageName` when set.
    var imageURL: URL? = nil
    /// A question to reflect on (detail screen).
    var question: String? = nil
    /// Meaning in each lens (detail only).
    var lenses: [Lens: String] = [:]
    /// Slugs of related symbols (detail only).
    var related: [String] = []
}

enum AppTab: String, CaseIterable, Hashable, Sendable {
    case today, journal, library
}

enum Route: Hashable, Sendable {
    case settings
    /// Settings -> Voice.
    case voice
    case interpretation(Dream.ID)
    case symbol(LibrarySymbol.ID)
}
