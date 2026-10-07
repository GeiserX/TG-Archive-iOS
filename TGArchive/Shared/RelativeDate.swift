import Foundation

/// The short date of a list row: the time today, "Yesterday", the weekday within the last week, the day
/// and month this year, the full date before that.
enum RelativeDate {
    static func string(for date: Date, now: Date = .now, calendar: Calendar = .current,
                       locale: Locale = .current) -> String {
        var calendar = calendar
        calendar.locale = locale
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        switch days {
        case ..<1:
            // Today, or a date ahead of this device's clock.
            return days == 0 ? date.formatted(style.hour().minute()) : date.formatted(style.day().month().year())
        case 1:
            return String(localized: "date.yesterday")
        case 2..<7:
            return date.formatted(style.weekday(.wide))
        default:
            if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
                return date.formatted(style.day().month(.abbreviated))
            }
            return date.formatted(style.day().month(.abbreviated).year())
        }
    }
}
