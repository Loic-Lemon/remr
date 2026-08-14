import XCTest
@testable import remr

final class SnoozeCalculatorTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int,
                      _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return calendar.date(from: components)!
    }

    private func assertChoice(_ choice: SnoozeChoice,
                              now: Date,
                              expected: Date,
                              file: StaticString = #filePath,
                              line: UInt = #line) {
        guard let result = SnoozeCalculator.date(for: choice, now: now, calendar: calendar) else {
            XCTFail("expected a date for \(choice)", file: file, line: line)
            return
        }
        XCTAssertEqual(result.date, expected, file: file, line: line)
        XCTAssertTrue(result.hasTime, "all preset snoozes are timed", file: file, line: line)
    }

    func testOneHourIsExactElapsedHour() {
        let now = date(2026, 8, 11, 12, 34, 56)
        assertChoice(.oneHour,
                     now: now,
                     expected: now.addingTimeInterval(3600))
    }

    func testLaterTodayUsesCurrentCalendarDayAtFive() {
        let now = date(2026, 8, 11, 8, 15)
        assertChoice(.laterToday,
                     now: now,
                     expected: date(2026, 8, 11, 17))
    }

    func testTomorrowChoicesCrossMidnightAndMonthBoundary() {
        let now = date(2026, 1, 31, 23, 55)
        assertChoice(.tomorrowMorning,
                     now: now,
                     expected: date(2026, 2, 1, 9))
        assertChoice(.tomorrowEvening,
                     now: now,
                     expected: date(2026, 2, 1, 18))
    }

    func testNextMondayFromWeekendCrossesMonthBoundary() {
        // January 31, 2027 is Sunday; the next Monday is February 1.
        let now = date(2027, 1, 31, 14)
        assertChoice(.nextMonday,
                     now: now,
                     expected: date(2027, 2, 1, 9))
    }

    func testNextMondayIsStrictlyAfterCurrentMonday() {
        let now = date(2026, 8, 10, 8) // Monday
        assertChoice(.nextMonday,
                     now: now,
                     expected: date(2026, 8, 17, 9))
    }

    func testThisWeekendFromFridayTargetsSaturday() {
        let now = date(2026, 8, 14, 14) // Friday
        assertChoice(.thisWeekend,
                     now: now,
                     expected: date(2026, 8, 15, 9))
    }

    func testThisWeekendFromSaturdayTargetsSunday() {
        let now = date(2026, 8, 15, 8) // Saturday
        assertChoice(.thisWeekend,
                     now: now,
                     expected: date(2026, 8, 16, 9))
    }

    func testThisWeekendFromSundayTargetsNextSaturday() {
        let now = date(2026, 8, 16, 10) // Sunday
        assertChoice(.thisWeekend,
                     now: now,
                     expected: date(2026, 8, 22, 9))
    }

    func testThisWeekendFromSaturdayCrossesMonthBoundary() {
        let now = date(2026, 1, 31, 12) // Saturday
        assertChoice(.thisWeekend,
                     now: now,
                     expected: date(2026, 2, 1, 9))
    }

    func testDayArithmeticSurvivesSpringForward() {
        // At 01:30, adding one elapsed hour crosses the missing 02:00 hour.
        let now = date(2026, 3, 8, 1, 30)
        assertChoice(.oneHour,
                     now: now,
                     expected: date(2026, 3, 8, 3, 30))
        assertChoice(.tomorrowMorning,
                     now: now,
                     expected: date(2026, 3, 9, 9))
    }

    func testDayArithmeticSurvivesFallBack() {
        let now = date(2026, 11, 1, 0, 30)
        assertChoice(.tomorrowEvening,
                     now: now,
                     expected: date(2026, 11, 2, 18))
    }
}
