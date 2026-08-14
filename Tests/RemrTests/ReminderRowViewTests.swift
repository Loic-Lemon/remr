import EventKit
import XCTest
@testable import remr

/// Display-only coverage for the recurrence indicator rendered in the row's
/// meta line. Fixtures never save through EventKit; they only exercise the
/// summary formatting for rules set in Reminders.app.
final class ReminderRowViewTests: XCTestCase {

    private func rule(_ frequency: EKRecurrenceFrequency, interval: Int) -> EKRecurrenceRule {
        EKRecurrenceRule(recurrenceWith: frequency, interval: interval, end: nil)
    }

    private func summary(frequency: EKRecurrenceFrequency, interval: Int) -> String? {
        ReminderRowView.recurrenceSummary(for: rule(frequency, interval: interval))
    }

    func testNilWhenNoRecurrenceRule() {
        let reminder = EKReminder(eventStore: EKEventStore())
        reminder.title = "Take out trash"
        reminder.recurrenceRules = nil

        let first = reminder.recurrenceRules?.first
        XCTAssertNil(first.flatMap(ReminderRowView.recurrenceSummary(for:)))
    }

    func testWeeklyIntervalOne() {
        XCTAssertEqual(summary(frequency: .weekly, interval: 1), "Repeats weekly")
    }

    func testWeeklyIntervalTwo() {
        XCTAssertEqual(summary(frequency: .weekly, interval: 2), "Repeats every 2 weeks")
    }

    func testDailyIntervalOne() {
        XCTAssertEqual(summary(frequency: .daily, interval: 1), "Repeats daily")
    }

    func testDailyIntervalThree() {
        XCTAssertEqual(summary(frequency: .daily, interval: 3), "Repeats every 3 days")
    }

    func testMonthlyIntervalOne() {
        XCTAssertEqual(summary(frequency: .monthly, interval: 1), "Repeats monthly")
    }

    func testMonthlyIntervalSix() {
        XCTAssertEqual(summary(frequency: .monthly, interval: 6), "Repeats every 6 months")
    }

    func testYearlyIntervalOne() {
        XCTAssertEqual(summary(frequency: .yearly, interval: 1), "Repeats yearly")
    }

    func testYearlyIntervalFour() {
        XCTAssertEqual(summary(frequency: .yearly, interval: 4), "Repeats every 4 years")
    }

    func testFirstRuleWinsWhenMultipleRules() {
        let reminder = EKReminder(eventStore: EKEventStore())
        reminder.title = "Water plants"
        reminder.recurrenceRules = [
            rule(.weekly, interval: 1),
            rule(.monthly, interval: 1),
        ]

        let first = reminder.recurrenceRules?.first
        XCTAssertEqual(first.flatMap(ReminderRowView.recurrenceSummary(for:)), "Repeats weekly")
    }
}
