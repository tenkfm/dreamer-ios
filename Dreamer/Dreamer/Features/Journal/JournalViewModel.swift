import Foundation
import Observation
import UIKit

/// 12 Journal: the month summary, the dreams grouped by week (newest first, more pages as the
/// list scrolls), search, pull-to-refresh and deletion.
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
        /// Mock mode: the asset catalog image.
        var assetName: String?
        var thumbnailURL: URL?
        var emotion: Emotion?
        /// Search: the matching fragment, matched words in `**`.
        var snippet: String?
    }

    /// One week of the journal (`weekOf` = its Monday).
    struct Section: Identifiable, Equatable {
        var id: Date
        var title: String
        var rows: [Row]
    }

    var isSearching = false
    var query = "" { didSet { if query != oldValue { scheduleSearch() } } }
    /// Search: only dreams with this emotion.
    var emotionFilter: Emotion? { didSet { if emotionFilter != oldValue { scheduleSearch() } } }
    /// The server's answer for the current query (nil: none yet, the device's list is filtered meanwhile).
    private(set) var searchResults: [DreamSummary]?
    private(set) var isSearchInFlight = false
    private(set) var isRefreshing = false
    /// The row waiting for "Delete" to be confirmed.
    var deleteCandidate: Row?
    var toastMessage: String?

    private let appState: AppState
    private let store: any DreamStore
    private let images: (any DreamImageLoading)?
    private let now: () -> Date
    private let calendar: Calendar
    private let dateFormatter: DreamDateFormatter
    private let searchDebounce: Duration
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init(appState: AppState, store: any DreamStore, images: (any DreamImageLoading)? = nil,
         now: @escaping () -> Date = Date.init, calendar: Calendar = .mondayFirst,
         searchDebounce: Duration = .milliseconds(350)) {
        self.appState = appState
        self.store = store
        self.images = images
        self.now = now
        self.calendar = calendar
        dateFormatter = DreamDateFormatter(calendar: calendar)
        self.searchDebounce = searchDebounce
    }

    // MARK: Summary

    private var dreamsThisMonth: [DreamSummary] {
        guard let month = calendar.dateInterval(of: .month, for: now()) else { return [] }
        return store.summaries.filter { month.contains($0.createdAt) }
    }

    var summary: Summary {
        let dreams = dreamsThisMonth
        let today = now()

        let symbolCounts = dreams.reduce(into: [String: Int]()) { counts, dream in
            for keyword in Set(dream.symbols) { counts[keyword, default: 0] += 1 }
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

    private var trimmedQuery: String {
        String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
    }

    private var hasSearchTerms: Bool { isSearching && (!trimmedQuery.isEmpty || emotionFilter != nil) }

    private var filteredDreams: [DreamSummary] {
        guard hasSearchTerms else { return store.summaries }
        return searchResults ?? localMatches(query: trimmedQuery, emotion: emotionFilter)
    }

    /// Offline, and while the server answers: titles and symbols of the dreams on the device.
    private func localMatches(query: String, emotion: Emotion?) -> [DreamSummary] {
        store.summaries.filter { dream in
            (emotion.map { dream.emotions.contains($0) } ?? true)
                && (query.isEmpty || (dream.title ?? "").localizedCaseInsensitiveContains(query)
                    || dream.symbols.contains { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    // MARK: Search

    /// Typing pauses briefly before asking the server; every change cancels the previous ask.
    private func scheduleSearch() {
        searchTask?.cancel()
        searchResults = nil
        guard hasSearchTerms else { return }
        let query = trimmedQuery
        let emotion = emotionFilter
        searchTask = Task { [weak self, searchDebounce] in
            try? await Task.sleep(for: searchDebounce)
            guard !Task.isCancelled else { return }
            await self?.search(query: query, emotion: emotion)
        }
    }

    private func search(query: String, emotion: Emotion?) async {
        isSearchInFlight = true
        defer { isSearchInFlight = false }
        do {
            let results = try await store.search(query: query.isEmpty ? nil : query, emotion: emotion)
            guard !Task.isCancelled else { return }
            searchResults = results
        } catch {
            guard !Task.isCancelled else { return }
            searchResults = localMatches(query: query, emotion: emotion)
        }
    }

    func toggleEmotionFilter(_ emotion: Emotion) {
        emotionFilter = emotionFilter == emotion ? nil : emotion
    }

    /// Weeks newest first, in the order the backend groups them.
    var sections: [Section] {
        var sections: [Section] = []
        for dream in filteredDreams {
            let week = calendar.startOfDay(for: dream.weekOf)
            if sections.last?.id == week {
                sections[sections.count - 1].rows.append(row(dream))
            } else {
                sections.append(Section(id: week, title: weekTitle(week), rows: [row(dream)]))
            }
        }
        return sections
    }

    var isEmpty: Bool { filteredDreams.isEmpty }

    var canLoadMore: Bool { store.canLoadMore && !isSearching }

    private func weekTitle(_ monday: Date) -> String {
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now())?.start ?? now()
        if calendar.isDate(monday, inSameDayAs: thisWeek) { return "This week" }
        if let last = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek), calendar.isDate(monday, inSameDayAs: last) {
            return "Last week"
        }
        let sunday = calendar.date(byAdding: .day, value: 6, to: monday) ?? monday
        return dateFormatter.range(from: monday, to: sunday)
    }

    private func row(_ dream: DreamSummary) -> Row {
        Row(id: dream.id,
            // Still being read: the backend has no title yet.
            title: dream.title ?? (dream.status == .failed ? "We couldn’t read this dream" : "Reading your dream…"),
            dateText: dateFormatter.day(dream.createdAt, now: now()),
            assetName: dream.assetName,
            thumbnailURL: dream.thumbnailURL,
            emotion: dream.emotions.first,
            snippet: hasSearchTerms ? dream.snippet : nil)
    }

    // MARK: Loading

    /// On opening and on pull-to-refresh. Offline the cached journal stays (the banner says why).
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            try await store.refresh()
        } catch .offline {
            // The cached list is what there is.
        } catch {
            if store.summaries.isEmpty { toastMessage = ErrorState(error).message }
        }
    }

    /// The last row appeared: the next page.
    func rowAppeared(_ row: Row) async {
        guard canLoadMore, row.id == filteredDreams.last?.id else { return }
        try? await store.loadMore()
    }

    func thumbnail(for row: Row) async -> UIImage? {
        guard let images, let url = row.thumbnailURL,
              let data = try? await images.thumbnailData(dreamID: row.id, url: url) else { return nil }
        return UIImage(data: data)
    }

    // MARK: Actions

    func toggleSearch() {
        isSearching.toggle()
        if !isSearching {
            query = ""
            emotionFilter = nil
        }
    }

    func open(_ row: Row) {
        appState.push(.interpretation(row.id), on: .journal)
    }

    func askToDelete(_ row: Row) {
        deleteCandidate = row
    }

    /// "Delete" confirmed: gone from the server, every device and this one.
    func confirmDelete() async {
        guard let row = deleteCandidate else { return }
        deleteCandidate = nil
        do {
            try await store.delete(id: row.id)
        } catch {
            toastMessage = ErrorState(error).kind == .offline
                ? "You’re offline. Try deleting again when you’re connected."
                : "Couldn’t delete this dream. Please try again."
        }
    }
}
