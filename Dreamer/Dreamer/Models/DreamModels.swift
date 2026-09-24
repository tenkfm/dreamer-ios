import Foundation

/// Interpretation style chosen in onboarding and in Settings -> Default lens.
enum Lens: String, CaseIterable, Codable, Sendable, Identifiable {
    case psychology, spiritual, dreamBook

    var id: Self { self }

    var title: String {
        switch self {
        case .psychology: "Psychology"
        case .spiritual: "Spiritual"
        case .dreamBook: "Dream book"
        }
    }

    var summary: String {
        switch self {
        case .psychology: "What your mind is working through"
        case .spiritual: "Signs, symbols and inner guidance"
        case .dreamBook: "Classic meanings of dream symbols"
        }
    }
}

enum Emotion: String, CaseIterable, Codable, Sendable, Identifiable {
    case fear, joy, anxiety, calm, confusion

    var id: Self { self }
    var title: String { rawValue.capitalized }
}

enum Recurrence: Int, CaseIterable, Codable, Sendable {
    case never, sometimes, often

    var title: String {
        switch self {
        case .never: "Never"
        case .sometimes: "Sometimes"
        case .often: "Often"
        }
    }
}

enum Goal: String, CaseIterable, Codable, Sendable, Identifiable {
    case understand, recurring, someone, remember

    var id: Self { self }

    var title: String {
        switch self {
        case .understand: "Understand my dreams"
        case .recurring: "A dream keeps coming back"
        case .someone: "Someone keeps appearing"
        case .remember: "Remember my dreams better"
        }
    }

    var glyph: Glyph {
        switch self {
        case .understand: .sparkle
        case .recurring: .stairs
        case .someone: .heart
        case .remember: .moon
        }
    }
}

/// Icon identifiers stored with content; rendered by `GlyphView` in the design system.
enum Glyph: String, CaseIterable, Codable, Sendable {
    case sparkle, stairs, heart, moon, house, person, water, bird, leaf, eye
}

struct DreamSymbol: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var meaning: String
    /// Short word used for pattern detection ("stairs").
    var keyword: String
    var glyph: Glyph

    init(id: UUID = UUID(), title: String, meaning: String, keyword: String, glyph: Glyph) {
        self.id = id
        self.title = title
        self.meaning = meaning
        self.keyword = keyword
        self.glyph = glyph
    }
}

struct Interpretation: Codable, Hashable, Sendable {
    /// All three lenses come back at once.
    var texts: [Lens: String]
    var forYou: String
    var readDurations: [Lens: TimeInterval]

    func text(for lens: Lens) -> String { texts[lens] ?? "" }
}

struct Dream: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var createdAt: Date
    var title: String
    var transcript: String
    var emotions: [Emotion]
    var recurrence: Recurrence
    var someoneSpecific: Bool
    var symbols: [DreamSymbol]
    var interpretation: Interpretation?
    /// Asset name in phase 1, URL later.
    var imageName: String?
    var notes: String

    /// Shown until the generated image is available.
    static let placeholderImageName = "SkyTall"

    init(id: UUID = UUID(), createdAt: Date, title: String, transcript: String, emotions: [Emotion],
         recurrence: Recurrence = .never, someoneSpecific: Bool = false, symbols: [DreamSymbol] = [],
         interpretation: Interpretation? = nil, imageName: String? = nil, notes: String = "") {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.transcript = transcript
        self.emotions = emotions
        self.recurrence = recurrence
        self.someoneSpecific = someoneSpecific
        self.symbols = symbols
        self.interpretation = interpretation
        self.imageName = imageName
        self.notes = notes
    }
}

/// What the user told us before analysis.
struct DreamDraft: Hashable, Sendable {
    var transcript: String = ""
    var emotions: [Emotion] = []
    var recurrence: Recurrence? = nil
    var someoneSpecific: Bool? = nil
}

enum AnalysisStep: Int, CaseIterable, Sendable {
    case reading, symbols, feelings, writing

    var title: String {
        switch self {
        case .reading: "Reading your dream"
        case .symbols: "Finding the key symbols"
        case .feelings: "Connecting with how you felt"
        case .writing: "Writing your interpretation"
        }
    }
}

enum AnalysisProgress: Sendable {
    /// The given step has completed.
    case completed(AnalysisStep)
    case finished(Dream)
}
