import XCTest
@testable import remr

final class NaturalLanguageParserTests: XCTestCase {

    /// Fixed `now`: 2026-08-09 12:47 local (Sunday).
    private let now: Date = {
        var c = DateComponents()
        c.year = 2026
        c.month = 8
        c.day = 9
        c.hour = 12
        c.minute = 47
        return Calendar.current.date(from: c)!
    }()

    private let fixture = ["Home", "Work", "Groceries", "AH"]

    private func parse(_ line: String, lists: [String]? = nil) -> ParsedReminder {
        NaturalLanguageParser.parse(line, now: now, calendar: .current, listNames: lists ?? fixture)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = hour
        c.minute = minute
        return Calendar.current.date(from: c)!
    }

    private func assertDate(_ actual: Date?, _ expected: Date, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        guard let actual else {
            XCTFail("expected date \(expected), got nil — \(message)", file: file, line: line)
            return
        }
        XCTAssertEqual(actual.timeIntervalSince1970, expected.timeIntervalSince1970,
                       accuracy: 60, message, file: file, line: line)
    }

    // MARK: - Cases

    func test1EndOfDayWithList() {
        let r = parse("Take out the trash before end of day @home")
        XCTAssertEqual(r.title, "Take out the trash")
        XCTAssertEqual(r.listToken, "home")
        XCTAssertTrue(r.listMatched)
        assertDate(r.dueDate, date(2026, 8, 9, 17, 0), "eod → today 17:00")
        XCTAssertTrue(r.hasTime)
        XCTAssertFalse(r.isInvalid)
    }

    func test2Tomorrow5pm() {
        let r = parse("Call mom tomorrow 5pm")
        assertDate(r.dueDate, date(2026, 8, 10, 17, 0), "tomorrow 17:00")
        XCTAssertTrue(r.hasTime)
        XCTAssertEqual(r.title, "Call mom")
    }

    func test3InThreeHours() {
        let r = parse("Buy milk in 3 hours")
        assertDate(r.dueDate, now.addingTimeInterval(3 * 3600), "now + 3h")
        XCTAssertTrue(r.hasTime, "detector gap → keyword sets hasTime")
        XCTAssertEqual(r.title, "Buy milk")
    }

    func test4March15DateOnly() {
        let r = parse("Pay rent on march 15")
        assertDate(r.dueDate, date(2027, 3, 15, 12, 0), "march 15 → noon, date-only")
        XCTAssertFalse(r.hasTime, "date-only = all-day")
        XCTAssertEqual(r.title, "Pay rent")
    }

    func test5ByFriday() {
        let r = parse("Submit report by friday")
        assertDate(r.dueDate, date(2026, 8, 14, 12, 0), "this Friday")
        XCTAssertFalse(r.hasTime)
        XCTAssertEqual(r.title, "Submit report")
    }

    func test6BareTimeRollover() {
        let r = parse("Water plants at 10am")
        assertDate(r.dueDate, date(2026, 8, 10, 10, 0), "10:00 already past → tomorrow 10:00")
        XCTAssertTrue(r.hasTime)
        XCTAssertEqual(r.title, "Water plants")
    }

    func test7BangBangHighPriority() {
        let r = parse("!! urgent meeting")
        XCTAssertEqual(r.priority, 1)
        XCTAssertEqual(r.title, "urgent meeting")
    }

    func test8LowPriorityKeyword() {
        let r = parse("low priority cleanup")
        XCTAssertEqual(r.priority, 9)
        XCTAssertEqual(r.title, "cleanup")
    }

    func test9ListTokenAH() {
        let r = parse("Groceries @AH")
        XCTAssertEqual(r.listToken, "AH")
        XCTAssertTrue(r.listMatched)
        XCTAssertEqual(r.title, "Groceries")
    }

    func test10TwoWordListToken() {
        let r = NaturalLanguageParser.parse("@home depot shopping", now: now, calendar: .current, listNames: ["Home Depot"])
        XCTAssertEqual(r.listToken, "home depot")
        XCTAssertTrue(r.listMatched)
        XCTAssertEqual(r.title, "shopping")
    }

    func test11UnmatchedList() {
        let r = parse("@unknown list task")
        XCTAssertEqual(r.listToken, "unknown")
        XCTAssertFalse(r.listMatched)
        XCTAssertEqual(r.title, "list task")
    }

    func test12AddressLocation() {
        let r = parse("Pick up package at 1 Apple Park Way, Cupertino CA 95014")
        XCTAssertEqual(r.locationPhrase, "1 Apple Park Way, Cupertino CA 95014")
        XCTAssertEqual(r.title, "Pick up package")
    }

    func test13TrailingAtPhrase() {
        let r = parse("Meet John at the office")
        XCTAssertEqual(r.locationPhrase, "the office")
        XCTAssertEqual(r.title, "Meet John")
    }

    func test14NoTokens() {
        let r = parse("Buy flowers for mom")
        XCTAssertEqual(r.title, "Buy flowers for mom")
        XCTAssertNil(r.listToken)
        XCTAssertNil(r.dueDate)
        XCTAssertEqual(r.priority, 0)
        XCTAssertNil(r.locationPhrase)
        XCTAssertFalse(r.isInvalid)
    }

    func test15DateOnlyIsInvalid() {
        let r = parse("tomorrow")
        XCTAssertTrue(r.isInvalid)
        assertDate(r.dueDate, date(2026, 8, 10, 12, 0))
    }

    func test16MultipleDates() {
        let r = parse("call john tomorrow at 5pm then email on friday")
        assertDate(r.dueDate, date(2026, 8, 10, 17, 0), "first match wins")
        XCTAssertEqual(r.title, "call john then email")
    }

    func test17LeadingConnectorStripped() {
        let r = parse("at 5pm dinner")
        assertDate(r.dueDate, date(2026, 8, 9, 17, 0))
        XCTAssertEqual(r.title, "dinner")
    }

    func test18InTwoDaysDetectorWins() {
        let r = parse("in 2 days")
        assertDate(r.dueDate, date(2026, 8, 11, 12, 0), "detector covers days; keyword must not double-fire")
        XCTAssertFalse(r.hasTime)
        XCTAssertTrue(r.isInvalid)
    }

    func test19Tonight() {
        let r = parse("clean kitchen tonight")
        assertDate(r.dueDate, date(2026, 8, 9, 18, 0))
        XCTAssertTrue(r.hasTime)
    }

    func test20ParseBulkSkipsEmptyLines() {
        let items = NaturalLanguageParser.parseBulk("a\n\nb", now: now, calendar: .current, listNames: fixture)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.map(\.original), ["a", "b"])
    }

    func test21TagsExtractedAndStripped() {
        let r = parse("buy milk #groceries #Urgent")
        XCTAssertEqual(r.tags, ["groceries", "Urgent"])
        XCTAssertEqual(r.title, "buy milk")
        XCTAssertFalse(r.isInvalid)
    }

    func test22TagOnlyLeavesNoTitle() {
        let r = parse("#groceries")
        XCTAssertEqual(r.tags, ["groceries"])
        XCTAssertTrue(r.isInvalid)
    }

    func test23TagBeforeDateDoesNotBecomeDueDate() {
        // Tag stripping runs before date extraction: "#tomorrow" must not
        // parse as a due date.
        let r = parse("meet #tomorrow")
        XCTAssertEqual(r.tags, ["tomorrow"])
        XCTAssertNil(r.dueDate)
        XCTAssertEqual(r.title, "meet")
    }

    func test24LaterMeansEndOfToday() {
        let r = parse("buy milk later")
        assertDate(r.dueDate, date(2026, 8, 9, 17, 0), "\"later\" = end of today (17:00)")
        XCTAssertTrue(r.hasTime)
        XCTAssertEqual(r.title, "buy milk")
    }

    func test25LaterTodayAlsoEndOfToday() {
        let r = parse("buy milk later today")
        assertDate(r.dueDate, date(2026, 8, 9, 17, 0))
        XCTAssertEqual(r.title, "buy milk")
    }

    func test26LaterInsideWordIgnored() {
        let r = parse("drink water")
        XCTAssertNil(r.dueDate)
        XCTAssertEqual(r.title, "drink water")
    }
}
