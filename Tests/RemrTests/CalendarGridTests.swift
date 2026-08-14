import EventKit
import XCTest
@testable import remr

final class CalendarGridTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US_POSIX")
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 2   // Monday
        return cal
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func reminder(_ title: String, due: DateComponents?) -> EKReminder {
        let reminder = EKReminder(eventStore: EKEventStore())
        reminder.title = title
        reminder.dueDateComponents = due
        return reminder
    }

    // MARK: - Grid math

    func testLeadingBlanksFirstOfMonth() {
        // August 1, 2026 is a Saturday; with a Monday-first calendar the 1st
        // needs five leading blank cells.
        XCTAssertEqual(CalendarGridMath.leadingBlanks(for: date(2026, 8, 1), calendar: calendar), 5)
    }

    func testDaysInMonthLeap() {
        XCTAssertEqual(CalendarGridMath.daysInMonth(for: date(2024, 2, 1), calendar: calendar), 29)
        XCTAssertEqual(CalendarGridMath.daysInMonth(for: date(2026, 2, 1), calendar: calendar), 28)
    }

    func testWeekdaySymbolsMondayFirst() {
        XCTAssertEqual(CalendarGridMath.weekdaySymbols(calendar: calendar).first, "M")
    }

    func testStartOfWeekMondayFirst() {
        // August 14, 2026 is a Friday; the week starts Monday the 10th.
        XCTAssertEqual(CalendarGridMath.startOfWeek(for: date(2026, 8, 14), calendar: calendar),
                       date(2026, 8, 10))
    }

    // MARK: - Bucketing

    func testBucketsGroupByDay() {
        let early = reminder("Early", due: calendar.dateComponents([.year, .month, .day, .hour, .minute],
                                                                   from: date(2026, 8, 12, 9)))
        let late = reminder("Late", due: calendar.dateComponents([.year, .month, .day, .hour, .minute],
                                                                 from: date(2026, 8, 12, 18)))
        let next = reminder("Next", due: calendar.dateComponents([.year, .month, .day],
                                                                 from: date(2026, 8, 13)))

        let buckets = CalendarBuckets.byDay([early, late, next], calendar: calendar)

        XCTAssertEqual(Set(buckets.keys), Set([date(2026, 8, 12), date(2026, 8, 13)]))
        XCTAssertEqual(buckets[date(2026, 8, 12)]?.count, 2)
        XCTAssertEqual(buckets[date(2026, 8, 13)]?.map(\.title), ["Next"])
    }

    func testBucketsDropsNilDue() {
        let buckets = CalendarBuckets.byDay([reminder("Undated", due: nil)], calendar: calendar)
        XCTAssertTrue(buckets.isEmpty)
    }

    func testSortedAllDayFirstThenTimed() {
        let timedLate = reminder("Timed late", due: calendar.dateComponents([.year, .month, .day, .hour, .minute],
                                                                            from: date(2026, 8, 12, 14, 30)))
        let allDay = reminder("All day", due: calendar.dateComponents([.year, .month, .day],
                                                                      from: date(2026, 8, 12)))
        let timedEarly = reminder("Timed early", due: calendar.dateComponents([.year, .month, .day, .hour, .minute],
                                                                              from: date(2026, 8, 12, 9)))

        let sorted = CalendarBuckets.sorted([timedLate, allDay, timedEarly], calendar: calendar)

        XCTAssertEqual(sorted.map(\.title), ["All day", "Timed early", "Timed late"])
    }

    func testAllDayMeansNoHourComponent() {
        let allDay = reminder("All day", due: calendar.dateComponents([.year, .month, .day],
                                                                      from: date(2026, 8, 12)))
        let timed = reminder("Timed", due: calendar.dateComponents([.year, .month, .day, .hour, .minute],
                                                                   from: date(2026, 8, 12, 8)))

        let sorted = CalendarBuckets.sorted([timed, allDay], calendar: calendar)

        XCTAssertEqual(sorted.map(\.title), ["All day", "Timed"])
        XCTAssertNil(allDay.dueDateComponents?.hour)
        XCTAssertNotNil(timed.dueDateComponents?.hour)
    }

    // MARK: - Overdue + reschedule

    func testIsOverdueBeforeStartOfToday() {
        let now = date(2026, 8, 14, 12)
        XCTAssertTrue(CalendarGridMath.isOverdue(date(2026, 8, 13, 23, 59), now: now, calendar: calendar))
        // Due today at midnight (start of day) is not overdue; neither is tomorrow.
        XCTAssertFalse(CalendarGridMath.isOverdue(date(2026, 8, 14), now: now, calendar: calendar))
        XCTAssertFalse(CalendarGridMath.isOverdue(date(2026, 8, 15), now: now, calendar: calendar))
    }

    func testRescheduleComponentsPreservesTimeOfDay() {
        let due = calendar.dateComponents([.year, .month, .day, .hour, .minute],
                                          from: date(2026, 8, 12, 9, 30))
        let target = CalendarGridMath.rescheduleComponents(due: due, to: date(2026, 8, 20), calendar: calendar)
        XCTAssertEqual(calendar.date(from: target), date(2026, 8, 20, 9, 30))
    }

    func testRescheduleComponentsKeepsAllDay() {
        let due = calendar.dateComponents([.year, .month, .day], from: date(2026, 8, 12))
        let target = CalendarGridMath.rescheduleComponents(due: due, to: date(2026, 8, 20), calendar: calendar)
        XCTAssertEqual(calendar.date(from: target), date(2026, 8, 20))
        XCTAssertNil(target.hour)
    }

    func testRescheduleComponentsNilDueBecomesAllDay() {
        let target = CalendarGridMath.rescheduleComponents(due: nil, to: date(2026, 8, 20), calendar: calendar)
        XCTAssertEqual(calendar.date(from: target), date(2026, 8, 20))
        XCTAssertNil(target.hour)
    }

    func testVisibleItemsHidesCompletedByDefault() {
        let incomplete = reminder("Incomplete", due: calendar.dateComponents([.year, .month, .day],
                                                                             from: date(2026, 8, 12)))
        let completed = reminder("Completed", due: calendar.dateComponents([.year, .month, .day],
                                                                           from: date(2026, 8, 12)))
        completed.isCompleted = true

        let visible = CalendarBuckets.visibleItems(all: [incomplete, completed],
                                                   completed: [completed],
                                                   showCompleted: false)
        XCTAssertEqual(visible.map(\.title), ["Incomplete"])
    }

    func testVisibleItemsShowsCompletedOnceWhenEnabled() {
        // EventKit's all-predicate can include completed items; the union must
        // dedupe so a completed reminder appears exactly once.
        let completed = reminder("Completed", due: calendar.dateComponents([.year, .month, .day],
                                                                           from: date(2026, 8, 12)))
        completed.isCompleted = true

        let visible = CalendarBuckets.visibleItems(all: [completed],
                                                   completed: [completed],
                                                   showCompleted: true)
        XCTAssertEqual(visible.map(\.title), ["Completed"])
    }
}
