import Foundation
import Observation

/// 12 Journal: monthly summary computed from stored dreams, list, and title search.
@MainActor
@Observable
final class JournalViewModel {
    struct Summary: Equatable {
        var title: String
        var mostFrequentSymbol: String?
        var dreamCount: Int
        /// Share of days so far this month with a dream caught.
        var ringProgress: Double
        /// Emotion counts, most frequent first.
        var distribution: [EmotionShare]
    }

    struct EmotionShare: Equatable, Identifiable {
        var emotion: Emotion
        var count: Int
        var id: Emotion { emotion }
    }

    struct Row: Identifiable, Equatable {
        let id: Dream.ID
        var title: String
        var dateText: String
        var imageName: String?
        var emotion: Emotion?
    }

    var isSearching = false
    var query = ""

    private let appState: AppState
    private let store: any DreamStore
    private let now: () -> Date
    private let calendar: Calendar
    private let dateFormatter: DreamDateFormatter

    init(appState: AppState, store: any DreamStore, now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.appState = appState
        self.store = store
        self.now = now
        self.calendar = calendar
        dateFormatter = DreamDateFormatter(calendar: calendar)
    }

    // MARK: Summary

    private var dreamsThisMonth: [Dream] {
        guard let month = calendar.dateInterval(of: .month, for: now()) else { return [] }
        return store.dreams.filter { month.contains($0.createdAt) }
    }

    var summary: Summary {
        let dreams = dreamsThisMonth
        let today = now()

        let symbolCounts = dreams.reduce(into: [String: Int]()) { counts, dream in
            for keyword in Set(dream.symbols.map(\.keyword)) { counts[keyword, default: 0] += 1 }
        }
        let topSymbol = symbolCounts.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key

        let daysWithDreams = Set(dreams.map { calendar.startOfDay(for: $0.createdAt) }).count
        let daysSoFar = calendar.component(.day, from: today)

        let emotionCounts = dreams.flatMap(\.emotions).reduce(into: [Emotion: Int]()) { $0[$1, default: 0] += 1 }
        let distribution = Emotion.allCases
            .compactMap { emotion in emotionCounts[emotion].map { EmotionShare(emotion: emotion, count: $0) } }
            .sorted { $0.count > $1.count }

        return Summary(
            title: "Your \(dateFormatter.month(today))",
            mostFrequentSymbol: topSymbol,
            dreamCount: dreams.count,
            ringProgress: daysSoFar > 0 ? min(1, Double(daysWithDreams) / Double(daysSoFar)) : 0,
            distribution: distribution
        )
    }

    // MARK: List

    private var filteredDreams: [Dream] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard isSearching, !trimmed.isEmpty else { return store.dreams }
        return store.dreams.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed) || $0.transcript.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var thisMonthRows: [Row] {
        guard let month = calendar.dateInterval(of: .month, for: now()) else { return [] }
        return filteredDreams.filter { month.contains($0.createdAt) }.map(row)
    }

    var earlierRows: [Row] {
        guard let month = calendar.dateInterval(of: .month, for: now()) else { return filteredDreams.map(row) }
        return filteredDreams.filter { !month.contains($0.createdAt) }.map(row)
    }

    var isEmpty: Bool { thisMonthRows.isEmpty && earlierRows.isEmpty }

    private func row(_ dream: Dream) -> Row {
        Row(id: dream.id,
            title: dream.title,
            dateText: dateFormatter.day(dream.createdAt, now: now()),
            imageName: dream.imageName,
            emotion: dream.emotions.first)
    }

    // MARK: Actions

    func toggleSearch() {
        isSearching.toggle()
        if !isSearching { query = "" }
    }

    func open(_ row: Row) {
        appState.push(.interpretation(row.id), on: .journal)
    }
}
