import EventKit
import Foundation

/// The list's chronological sections. A reminder lands in exactly one bucket
/// (first matching range wins, in declaration order); reminders with no due
/// date go to FUTURE. Week/month boundaries come from the calendar, so
/// locale-specific week starts are respected.
enum ReminderSection: String, CaseIterable {
    case ongoing = "ONGOING"
    case overdue = "OVERDUE"
    case today = "TODAY"
    case thisWeek = "THIS WEEK"
    case nextWeek = "NEXT WEEK"
    case thisMonth = "THIS MONTH"
    case nextMonth = "NEXT MONTH"
    case future = "FUTURE"

    /// Calendar boundaries the bucketing ranges are built from, computed once
    /// per refresh of the list.
    struct Bounds {
        let startOfToday: Date
        let startOfTomorrow: Date
        let startOfNextWeek: Date
        let startOfWeekAfterNext: Date
        let startOfNextMonth: Date
        let startOfMonthAfterNext: Date
    }

    static func bounds(now: Date = Date(), calendar: Calendar = .current) -> Bounds {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
        // Week = calendar week-of-year (e.g. Monday–Sunday in en_US): "this
        // week" is the remainder of the current week after today, "next week"
        // the following one. Month boundaries are calendar month starts.
        let startOfNextWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.end ?? startOfTomorrow
        let startOfWeekAfterNext = calendar.date(byAdding: .day, value: 7, to: startOfNextWeek) ?? startOfNextWeek
        let startOfNextMonth = calendar.dateInterval(of: .month, for: now)?.end ?? startOfWeekAfterNext
        let startOfMonthAfterNext = calendar.date(byAdding: .month, value: 1, to: startOfNextMonth) ?? startOfNextMonth
        return Bounds(startOfToday: startOfToday,
                      startOfTomorrow: startOfTomorrow,
                      startOfNextWeek: startOfNextWeek,
                      startOfWeekAfterNext: startOfWeekAfterNext,
                      startOfNextMonth: startOfNextMonth,
                      startOfMonthAfterNext: startOfMonthAfterNext)
    }

    /// The section a due date belongs to; nil due dates sort into FUTURE.
    /// Precedence order means a date is never double-counted: "this week"
    /// wins over "this month" when the current week spills into the next
    /// month, and so on.
    static func section(for due: Date?, now: Date = Date(), calendar: Calendar = .current) -> ReminderSection {
        section(for: due, bounds: bounds(now: now, calendar: calendar))
    }

    /// Bounds-taking variant for callers that bucket many reminders at once
    /// (compute `bounds()` once, reuse it).
    static func section(for due: Date?, bounds: Bounds) -> ReminderSection {
        guard let due else { return .future }
        switch due {
        case ..<bounds.startOfToday: return .overdue
        case bounds.startOfToday..<bounds.startOfTomorrow: return .today
        case bounds.startOfTomorrow..<bounds.startOfNextWeek: return .thisWeek
        case bounds.startOfNextWeek..<bounds.startOfWeekAfterNext: return .nextWeek
        case bounds.startOfWeekAfterNext..<bounds.startOfNextMonth: return .thisMonth
        case bounds.startOfNextMonth..<bounds.startOfMonthAfterNext: return .nextMonth
        default: return .future
        }
    }
    /// The section a reminder belongs to when ongoing markers are considered.
    /// Ongoing reminders are pinned ahead of chronological buckets without
    /// changing their native due date.
    static func section(for due: Date?, ongoing: Bool, bounds: Bounds) -> ReminderSection {
        if ongoing { return .ongoing }
        return section(for: due, bounds: bounds)
    }
}
