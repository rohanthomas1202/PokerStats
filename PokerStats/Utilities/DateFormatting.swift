import Foundation

enum DateFormatting {
    private static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static let monthDayYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    private static let dayOfWeek: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    private static let shortDayOfWeek: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    /// "Mar 8"
    static func formatMonthDay(_ date: Date) -> String {
        monthDay.string(from: date)
    }

    /// "Mar 8, 2026"
    static func formatFull(_ date: Date) -> String {
        monthDayYear.string(from: date)
    }

    /// "Saturday"
    static func formatDayOfWeek(_ date: Date) -> String {
        dayOfWeek.string(from: date)
    }

    /// "Sat"
    static func formatShortDay(_ date: Date) -> String {
        shortDayOfWeek.string(from: date)
    }

    /// "3:45 PM"
    static func formatTime(_ date: Date) -> String {
        time.string(from: date)
    }

    /// "March 2026"
    static func formatMonthYear(_ date: Date) -> String {
        monthYear.string(from: date)
    }
}
