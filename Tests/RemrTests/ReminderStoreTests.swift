import EventKit
import XCTest
@testable import remr

@MainActor
final class ReminderStoreTests: XCTestCase {

    /// EventKit's date-range predicates misfile all-day reminders (all-day
    /// "today" comes back as overdue), so ReminderStore buckets by due date
    /// in Swift. This defends that contract.
    func testBucketAllDayTodayLandsInToday() {
        let store = EKEventStore()
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: start)!

        func reminder(_ comps: DateComponents?) -> EKReminder {
            let r = EKReminder(eventStore: store)
            r.dueDateComponents = comps
            return r
        }
        let allDayToday = reminder(cal.dateComponents([.year, .month, .day], from: start))
        let timedToday = reminder(cal.dateComponents([.year, .month, .day, .hour],
                                                    from: cal.date(byAdding: .hour, value: 3, to: start)!))
        let allDayYesterday = reminder(cal.dateComponents([.year, .month, .day],
                                                         from: cal.date(byAdding: .day, value: -1, to: start)!))
        let noDue = reminder(nil)

        let result = ReminderStore.bucket([allDayToday, timedToday, allDayYesterday, noDue],
                                          startOfToday: start, startOfTomorrow: tomorrow, calendar: cal)

        XCTAssertTrue(result.today.contains { $0 === allDayToday }, "all-day today must be TODAY, not overdue")
        XCTAssertTrue(result.today.contains { $0 === timedToday }, "timed today stays TODAY")
        XCTAssertTrue(result.overdue.contains { $0 === allDayYesterday }, "yesterday stays OVERDUE")
        XCTAssertFalse(result.overdue.contains { $0 === allDayToday })
        XCTAssertFalse(result.today.contains { $0 === noDue }, "nil due is neither bucket (LATER)")
        XCTAssertFalse(result.overdue.contains { $0 === noDue })
    }
}
