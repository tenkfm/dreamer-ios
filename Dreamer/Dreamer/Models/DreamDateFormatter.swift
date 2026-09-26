import Foundation

/// Relative dates used across Journal and Interpretation: "Yesterday", "Tuesday", "Sep 17".
struct DreamDateFormatter {
    var calendar: Calendar = .current
    var locale: Locale = Locale(identifier: "en_US")

    func day(_ date: Date, now: Date = .now) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "Today") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return String(localized: "Yesterday") }
        let startOfToday = calendar.startOfDay(for: now)
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: startOfToday).day,
           (0..<7).contains(days) {
            return format(date, "EEEE")
        }
        return format(date, String(localized: "MMM d"))
    }

    /// "Yesterday · 7:12 AM"
    func dayAndTime(_ date: Date, now: Date = .now) -> String {
        "\(day(date, now: now)) · \(format(date, "h:mm a"))"
    }

    /// "September"
    func month(_ date: Date) -> String {
        format(date, "LLLL")
    }

    /// "Sep 8 - 14", or "Aug 30 - Sep 5" across months.
    func range(from start: Date, to end: Date) -> String {
        let sameMonth = calendar.isDate(start, equalTo: end, toGranularity: .month)
        return "\(format(start, "MMM d")) - \(format(end, sameMonth ? "d" : String(localized: "MMM d")))"
    }

    private func format(_ date: Date, _ template: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = template
        return formatter.string(from: date)
    }
}
