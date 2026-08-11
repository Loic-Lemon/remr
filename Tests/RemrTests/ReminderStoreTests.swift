import XCTest
import Foundation

@testable import remr

/// The chronological sections are bucketed in Swift (never EventKit date-range
/// predicates, which misfile all-day reminders), so ReminderSection is the
/// single source of truth for overdue/today/this-week/... grouping.
final class ReminderStoreTests: XCTestCase {

    /// Fixed `now`: 2026-08-11 12:00 local (a Tuesday, mid-month).
    private let now: Date = {
        var c = DateComponents()
        c.year = 2026
        c.month = 8
        c.day = 11
        c.hour = 12
        return Calendar.current.date(from: c)!
    }()

    private func date(_ day: Int, _ hour: Int = 12) -> Date {
        var c = DateComponents()
        c.year = 2026
        c.month = 8
        c.day = day
        c.hour = hour
        return Calendar.current.date(from: c)!
    }

    func testSectionsInChronologicalOrder() {
        let cal = Calendar.current
        let bounds = ReminderSection.bounds(now: now, calendar: cal)

        // Aug 2026: the 11th is a Tuesday; its week runs Mon 10 – Sun 16,
        // next week Mon 17 – Sun 23; the month ends Aug 31.
        let cases: [(Date?, ReminderSection)] = [
            (date(10), .overdue),      // Monday, before today
            (date(11), .today),        // today
            (date(12), .thisWeek),     // rest of the current week
            (date(17), .nextWeek),     // following week
            (date(24), .thisMonth),    // later this month (beyond next week)
            (date(30), .thisMonth),    // still this month
            (date(31, 23), .thisMonth),
            (nil, .future),            // no due date
        ]
        for (due, expected) in cases {
            XCTAssertEqual(ReminderSection.section(for: due, bounds: bounds), expected,
                           "due \(String(describing: due)) should be \(expected.rawValue)")
        }
    }

    func testOngoingSectionTakesPrecedenceOverDueDate() {
        let bounds = ReminderSection.bounds(now: now, calendar: .current)
        let cases: [(Date?, ReminderSection)] = [
            (date(10), .overdue),
            (date(11), .today),
            (date(12), .thisWeek),
            (nil, .future),
        ]

        for (due, chronologicalSection) in cases {
            XCTAssertEqual(ReminderSection.section(for: due, ongoing: true, bounds: bounds), .ongoing,
                           "ongoing due \(String(describing: due)) should be pinned")
            XCTAssertEqual(ReminderSection.section(for: due, ongoing: false, bounds: bounds), chronologicalSection,
                           "non-ongoing due \(String(describing: due)) should remain \(chronologicalSection.rawValue)")
        }
    }

    func testNextMonthAndFuture() {
        let cal = Calendar.current
        let bounds = ReminderSection.bounds(now: now, calendar: cal)
        var c = DateComponents()
        c.year = 2026
        c.month = 9
        c.day = 5
        let nextMonth = cal.date(from: c)!
        XCTAssertEqual(ReminderSection.section(for: nextMonth, bounds: bounds), .nextMonth)

        c.year = 2027
        let farFuture = cal.date(from: c)!
        XCTAssertEqual(ReminderSection.section(for: farFuture, bounds: bounds), .future)
    }

    func testAllDayTodayIsTodayNotOverdue() {
        // The regression that motivated Swift-side bucketing: an all-day
        // reminder due today must land in TODAY, never OVERDUE.
        let startOfToday = calStartOfDay(for: now)
        let allDayToday = date(11)
        XCTAssertEqual(ReminderSection.section(for: allDayToday, now: startOfToday, calendar: .current), .today)
        XCTAssertNotEqual(ReminderSection.section(for: allDayToday, now: startOfToday, calendar: .current), .overdue)
    }

    private func calStartOfDay(for d: Date) -> Date {
        Calendar.current.startOfDay(for: d)
    }

    func testDateComponentsRespectsAllDayAndTimedDates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 11
        components.hour = 12
        components.minute = 34
        components.second = 56
        let date = calendar.date(from: components)!

        XCTAssertNil(ReminderStore.dateComponents(for: nil, hasTime: true, calendar: calendar))

        let allDay = ReminderStore.dateComponents(for: date, hasTime: false, calendar: calendar)
        XCTAssertEqual(allDay?.year, 2026)
        XCTAssertEqual(allDay?.month, 8)
        XCTAssertEqual(allDay?.day, 11)
        XCTAssertNil(allDay?.hour)
        XCTAssertNil(allDay?.minute)
        XCTAssertNil(allDay?.second)

        let timed = ReminderStore.dateComponents(for: date, hasTime: true, calendar: calendar)
        XCTAssertEqual(timed?.year, 2026)
        XCTAssertEqual(timed?.month, 8)
        XCTAssertEqual(timed?.day, 11)
        XCTAssertEqual(timed?.hour, 12)
        XCTAssertEqual(timed?.minute, 34)
        XCTAssertEqual(timed?.second, 56)
    }

    func testDeletedReminderDecodingDefaultsCompletionFields() throws {
        let original = DeletedReminder(id: UUID(), title: "legacy", notes: nil,
                                       dueDate: nil, isAllDay: false, priority: 0,
                                       calendarIdentifier: nil, location: nil,
                                       deletedAt: now)
        let encoded = try JSONEncoder().encode(original)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "isCompleted")
        object.removeValue(forKey: "completionDate")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(DeletedReminder.self, from: legacyData)
        XCTAssertFalse(decoded.isCompleted)
        XCTAssertNil(decoded.completionDate)
    }
}
