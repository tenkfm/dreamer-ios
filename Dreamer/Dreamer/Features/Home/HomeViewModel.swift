import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    private let appState: AppState
    private let store: any DreamStore
    private let catalog: any SymbolCatalog
    /// The backend's insights; nil in mock mode, where they are computed from the stored dreams.
    private let insights: InsightStore?
    private let now: () -> Date
    private let calendar: Calendar

    init(appState: AppState, store: any DreamStore, catalog: any SymbolCatalog, insights: InsightStore? = nil,
         now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.appState = appState
        self.store = store
        self.catalog = catalog
        self.insights = insights
        self.now = now
        var calendar = calendar
        calendar.firstWeekday = 2 // Week strip runs Monday..Sunday.
        self.calendar = calendar
    }

    // MARK: Greeting

    var greeting: String {
        let hour = calendar.component(.hour, from: now())
        let partOfDay = switch hour {
        case 4..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
        let name = appState.userName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? partOfDay : "\(partOfDay), \(name)"
    }

    let subtitle = "Tap to tell last night’s dream"

    // MARK: Week

    private var weekDates: [Date] {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: now())?.start else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var dreamsThisWeek: [DreamSummary] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now()) else { return [] }
        return store.summaries.filter { week.contains($0.createdAt) }
    }

    var weekDays: [WeekDayState] {
        if let week = insights?.week {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.dateFormat = "EEEE"
            return week.days.enumerated().map { index, day in
                WeekDayState(id: index, letter: day.letter, isDone: day.caught, accessibilityName: formatter.string(from: day.date))
            }
        }
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "EEEE"
        let dreams = dreamsThisWeek
        return weekDates.enumerated().map { index, day in
            WeekDayState(id: index,
                         letter: letters[index],
                         isDone: dreams.contains { calendar.isDate($0.createdAt, inSameDayAs: day) },
                         accessibilityName: formatter.string(from: day))
        }
    }

    var weekCaption: String {
        let count = insights?.week?.count ?? dreamsThisWeek.count
        return switch count {
        case 0: "No dreams caught yet this week"
        case 1: "1 dream caught this week"
        default: "\(count) dreams caught this week"
        }
    }

    // MARK: Insight

    /// The backend's morning insight, or (mock mode) the most repeated symbol this week.
    var insight: String? {
        if let insights { return insights.morning?.text }
        let dreams = dreamsThisWeek
        let counts = dreams.reduce(into: [String: Int]()) { counts, dream in
            for keyword in Set(dream.symbols) { counts[keyword, default: 0] += 1 }
        }
        guard let top = counts.max(by: { ($0.value, $1.key) < ($1.value, $0.key) }), top.value >= 2 else { return nil }
        return "\(top.key.capitalized) appeared in \(top.value) of your dreams this week."
    }

    let insightPlaceholder = "Tell a dream each morning and your patterns will appear here."

    /// The backend says nothing yet (null): no card, except for a new user, who gets the invitation.
    var showsInsightCard: Bool {
        insight != nil || insights == nil || (store.summaries.isEmpty && (insights?.month?.dreamCount ?? 0) == 0)
    }

    /// Changes when a dream is added or removed, so the insights are asked again.
    var dreamCount: Int { store.summaries.count }

    func refreshInsights() async {
        await insights?.refresh()
    }

    // MARK: Library preview

    var featuredSymbols: [LibrarySymbol] {
        Array(catalog.symbols.filter { $0.categories.contains(.popular) }.prefix(6))
    }

    // MARK: Actions

    var isNightMode: Bool { appState.isNightMode }

    func openSettings() { appState.push(.settings, on: .today) }
    func toggleNightMode() { appState.toggleNightMode() }
    func startRecording() { appState.presentRecordFlow() }
    func seePattern() { appState.open(.journal) }
    func seeAllSymbols() { appState.open(.library) }
    func open(_ symbol: LibrarySymbol) { appState.open(.library, route: .symbol(symbol.id)) }
}
