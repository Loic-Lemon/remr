import Foundation
import XCTest
@testable import remr

final class ReminderSectionsTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testTomorrowHasItsOwnSection() {
        let now = date(2026, 9, 7) // Monday

        XCTAssertEqual(ReminderSection.section(for: date(2026, 9, 8),
                                               now: now,
                                               calendar: calendar), .tomorrow)
        XCTAssertEqual(ReminderSection.section(for: date(2026, 9, 9),
                                               now: now,
                                               calendar: calendar), .thisWeek)
    }
}
