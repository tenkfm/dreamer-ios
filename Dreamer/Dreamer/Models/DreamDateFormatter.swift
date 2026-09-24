import Foundation

/// Relative dates used across Journal and Interpretation: "Yesterday", "Tuesday", "Sep 17".
struct DreamDateFormatter {
    var calendar: Calendar = .current
    var locale: Locale = Locale(identifier: "en_US")

    func day(_ date: Date, now: Date = .now) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        let startOfToday = calendar.startOfDay(for: now)
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: startOfToday).day,
           (0..<7).contains(days) {
            return format(date, "EEEE")
        }
        return format(date, "MMM d")
    }

    /// "Yesterday · 7:12 AM"
    func dayAndTime(_ date: Date, now: Date = .now) -> String {
        "\(day(date, now: now)) · \(format(date, "h:mm a"))"
    }

    /// "September"
    func month(_ date: Date) -> String {
        format(date, "LLLL")
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
