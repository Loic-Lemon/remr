import EventKit
import Foundation

/// Pure grid math shared by the reminder picker grid and the calendar views.
enum CalendarGridMath {
    /// Weekday headers rotated to the calendar's first weekday.
    static func weekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...]) + Array(symbols[..<first])
    }
    /// Empty leading cells so the 1st lands in its weekday column.
    static func leadingBlanks(for month: Date, calendar: Calendar) -> Int {
        (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
    }
    static func daysInMonth(for month: Date, calendar: Calendar) -> Int {
        calendar.range(of: .day, in: .month, for: month)?.count ?? 30
    }
    /// startOfDay of the day containing `date`.
    static func startOfDay(for date: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: date)
    }
    /// startOfDay of the first day of `date`'s week (locale firstWeekday).
    static func startOfWeek(for date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }
    /// startOfDay of the first day of `date`'s month.
    static func startOfMonth(for date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }
    /// True when `date` falls before the start of `now`'s day (past-due).
    static func isOverdue(_ date: Date, now: Date, calendar: Calendar) -> Bool {
        date < calendar.startOfDay(for: now)
    }
    /// Day components for `targetDay`, keeping a timed reminder's hour/minute
    /// (all-day and nil-due reminders stay all-day).
    static func rescheduleComponents(due: DateComponents?, to targetDay: Date, calendar: Calendar) -> DateComponents {
        var target = calendar.dateComponents([.year, .month, .day], from: targetDay)
        if let due, due.hour != nil {
            target.hour = due.hour
            target.minute = due.minute
        }
        return target
    }
}

/// Day-indexed reminder grouping for the calendar views (tested in Step 6).
enum CalendarBuckets {
    /// startOfDay -> incomplete reminders due that day. Reminders without a
    /// due date are omitted (they have no calendar slot).
    static func byDay(_ reminders: [EKReminder], calendar: Calendar = .current) -> [Date: [EKReminder]] {
        var map: [Date: [EKReminder]] = [:]
        for r in reminders {
            guard let due = r.dueDateComponents.flatMap({ calendar.date(from: $0) }) else { continue }
            map[calendar.startOfDay(for: due), default: []].append(r)
        }
        return map
    }
    /// All-day (hour == nil) first, then timed ascending; nil-due last by title.
    static func sorted(_ reminders: [EKReminder], calendar: Calendar = .current) -> [EKReminder] {
        reminders.sorted { lhs, rhs in
            let l = lhs.dueDateComponents, r = rhs.dueDateComponents
            let lAllDay = l?.hour == nil, rAllDay = r?.hour == nil
            if lAllDay != rAllDay { return lAllDay }
            let ld = l.flatMap { calendar.date(from: $0) }
            let rd = r.flatMap { calendar.date(from: $0) }
            switch (ld, rd) {
            case let (a?, b?): return a < b
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return (lhs.title ?? "") < (rhs.title ?? "")
            }
        }
    }

    /// The reminders the calendar shows: incomplete only by default, or the
    /// deduplicated union of incomplete + completed. EventKit's
    /// `predicateForReminders` can include completed items, so the incomplete
    /// branch filters explicitly and the union dedupes by identifier.
    static func visibleItems(all: [EKReminder],
                             completed: [EKReminder],
                             showCompleted: Bool) -> [EKReminder] {
        if showCompleted {
            var seen = Set<String>()
            return (all + completed).filter { seen.insert($0.calendarItemIdentifier).inserted }
        }
        return all.filter { !$0.isCompleted }
    }
}
