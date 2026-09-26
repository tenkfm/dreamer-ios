import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    private let appState: AppState
    private let store: any DreamStore
    private let catalog: any SymbolCatalog
    private let now: () -> Date
    private let calendar: Calendar

    init(appState: AppState, store: any DreamStore, catalog: any SymbolCatalog,
         now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.appState = appState
        self.store = store
        self.catalog = catalog
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
        let count = dreamsThisWeek.count
        return switch count {
        case 0: "No dreams caught yet this week"
        case 1: "1 dream caught this week"
        default: "\(count) dreams caught this week"
        }
    }

    // MARK: Insight

    /// The most repeated symbol this week, if any repeats.
    var insight: String? {
        let dreams = dreamsThisWeek
        let counts = dreams.reduce(into: [String: Int]()) { counts, dream in
            for keyword in Set(dream.symbols) { counts[keyword, default: 0] += 1 }
        }
        guard let top = counts.max(by: { ($0.value, $1.key) < ($1.value, $0.key) }), top.value >= 2 else { return nil }
        return "\(top.key.capitalized) appeared in \(top.value) of your dreams this week."
    }

    let insightPlaceholder = "Tell a dream each morning and your patterns will appear here."

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
