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

    /// Fixed `now` for the weekday cases: 2026-08-11 13:26 local (Tuesday).
    private let tuesdayNow: Date = {
        var c = DateComponents()
        c.year = 2026
        c.month = 8
        c.day = 11
        c.hour = 13
        c.minute = 26
        return Calendar.current.date(from: c)!
    }()

    private let fixture = ["Home", "Work", "Groceries", "AH"]

    private func parse(_ line: String, lists: [String]? = nil) -> ParsedReminder {
        NaturalLanguageParser.parse(line, now: now, calendar: .current, listNames: lists ?? fixture)
    }

    private func parseAt(_ line: String, now: Date, lists: [String]? = nil) -> ParsedReminder {
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
        XCTAssertTrue(r.diagnostics.isEmpty)
    }

    func test11UnmatchedList() {
        // A line that is only "@phrase" (no title words before the @) keeps
        // the unmatched-list shape: the @ stays in the title.
        let r = parse("@unknown list task")
        XCTAssertNil(r.listToken)
        XCTAssertFalse(r.listMatched)
        XCTAssertNil(r.locationPhrase)
        XCTAssertEqual(r.title, "@unknown list task")
        XCTAssertEqual(r.diagnostics, [.unmatchedList("unknown")])
    }

    func test11bAtSignPhraseBecomesLocation() {
        // "buy milk @the office" — an unmatched @ mid-line is a location
        // phrase, exactly like "at the office".
        let r = parse("buy milk @the office")
        XCTAssertEqual(r.locationPhrase, "the office")
        XCTAssertNil(r.listToken)
        XCTAssertFalse(r.listMatched)
        XCTAssertEqual(r.title, "buy milk")
        XCTAssertTrue(r.diagnostics.isEmpty)
    }

    func test11cAtSignPhraseWithDueDate() {
        let r = parse("buy milk @the office tomorrow")
        XCTAssertEqual(r.locationPhrase, "the office")
        assertDate(r.dueDate, date(2026, 8, 10, 12, 0), "location + due date combine")
        XCTAssertEqual(r.title, "buy milk")
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
        XCTAssertEqual(r.diagnostics, [.emptyTitle])
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
        XCTAssertEqual(r.diagnostics, [.emptyTitle])
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

    // MARK: - containsTag (tag filter rule)

    func test27ContainsTagExactToken() {
        XCTAssertTrue(NaturalLanguageParser.containsTag("groceries", in: "buy milk #groceries"))
        XCTAssertTrue(NaturalLanguageParser.containsTag("groceries", in: "buy milk #groceries #urgent"))
    }

    func test28ContainsTagCaseInsensitive() {
        XCTAssertTrue(NaturalLanguageParser.containsTag("urgent", in: "call #URGENT"))
        XCTAssertTrue(NaturalLanguageParser.containsTag("Urgent", in: "call #urgent"))
    }

    func test29ContainsTagNotSubstring() {
        // Prose mentions without a #token never match (unlike search).
        XCTAssertFalse(NaturalLanguageParser.containsTag("urgent", in: "an urgent matter"))
        XCTAssertFalse(NaturalLanguageParser.containsTag("groceries", in: "buy groceries"))
        // A different token containing the tag as a substring doesn't match.
        XCTAssertFalse(NaturalLanguageParser.containsTag("milk", in: "buy #milkman"))
    }

    func test30ContainsTagNoHashInput() {
        XCTAssertFalse(NaturalLanguageParser.containsTag("work", in: "no tags here"))
        XCTAssertFalse(NaturalLanguageParser.containsTag("work", in: ""))
    }

    // MARK: - Regression: UTF-16 safety, relative-date math, list matching

    func test31EmojiBeforeDateDoesNotCrash() {
        // Non-BMP characters shift NSRange (UTF-16) offsets away from
        // Character indices; the old conversion crashed on "🎉 party tomorrow".
        let r = parse("🎉 party tomorrow")
        XCTAssertEqual(r.title, "🎉 party")
        assertDate(r.dueDate, date(2026, 8, 10, 12, 0), "emoji before a date still parses")
        XCTAssertFalse(r.hasTime)
    }

    func test32EmojiBeforeListToken() {
        let r = parse("🏠 @home milk")
        XCTAssertEqual(r.listToken, "home")
        XCTAssertTrue(r.listMatched)
        XCTAssertEqual(r.title, "🏠 milk")
    }

    func test33InTwoDaysAtTimeKeepsTime() {
        // The relative-day rebase used to force noon, so a timed phrase
        // "in 2 days at 5pm" became an all-day noon due date.
        let r = parse("pay rent in 2 days at 5pm")
        assertDate(r.dueDate, date(2026, 8, 11, 17, 0), "timed relative date keeps 17:00")
        XCTAssertTrue(r.hasTime)
        XCTAssertEqual(r.title, "pay rent")
    }

    func test34InTwoWeeksAddsWeeksNotDays() {
        // The rebase ignored the unit: "in 2 weeks" landed 2 days out.
        let r = parse("submit in 2 weeks at 9am")
        assertDate(r.dueDate, date(2026, 8, 23, 9, 0), "2 weeks = 14 days, time preserved")
        XCTAssertTrue(r.hasTime)
        XCTAssertEqual(r.title, "submit")
    }

    func test35NextWeekdaySkipsCurrentWeek() {
        // "next tuesday" from a Sunday is the tuesday after the coming one
        // (8/18), not this week's tuesday (8/11).
        let r = parse("call next tuesday")
        assertDate(r.dueDate, date(2026, 8, 18, 12, 0), "\"next\" shifts a full week")
        XCTAssertEqual(r.title, "call")
    }

    func test36EmailAtSignIsNotAListToken() {
        // "john@home.example" used to match the "Home" list by substring and
        // get stripped from the title.
        let r = parse("Email john@home.example about the party")
        XCTAssertNil(r.listToken)
        XCTAssertFalse(r.listMatched)
        XCTAssertEqual(r.title, "Email john@home.example about the party")
        XCTAssertTrue(r.diagnostics.isEmpty)
    }

    // MARK: - Regression: autocomplete keywords, rollover, priority compounds

    func test37NextWeekPlus7Days() {
        // "next week" (autocomplete keyword) now resolves: exactly +7 days
        // from today at noon, all-day — consistent with "in 1 week".
        let r = parse("buy milk next week")
        assertDate(r.dueDate, date(2026, 8, 16, 12, 0), "next week → +7 days, noon")
        XCTAssertFalse(r.hasTime, "next week is all-day")
        XCTAssertEqual(r.title, "buy milk")
        XCTAssertFalse(r.isInvalid)
    }

    func test38ThisWeekEndsCurrentWeek() {
        // "this week" (autocomplete keyword) → last day of the current week,
        // noon. Compute the expectation with the same calendar call so the
        // locale-dependent week start can't drift the assertion.
        let r = parse("buy milk this week")
        let weekEnd = Calendar.current.dateInterval(of: .weekOfYear, for: now)!.end
        let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: weekEnd)!
        let expected = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: lastDay)!
        assertDate(r.dueDate, expected, "this week → last day of current week, noon")
        XCTAssertFalse(r.hasTime, "this week is all-day")
    }

    func test39TonightLateStaysToday() {
        // "tonight" after 18:00 must stay today 18:00, not roll to tomorrow.
        let r = NaturalLanguageParser.parse("clean kitchen tonight", now: date(2026, 8, 9, 19, 0),
                                            calendar: .current, listNames: fixture)
        assertDate(r.dueDate, date(2026, 8, 9, 18, 0), "tonight at 19:00 stays today")
        XCTAssertTrue(r.hasTime)
    }

    func test40LaterEodAfterEodHourStaysToday() {
        // "later"/"eod"/"end of day" typed after 17:00 are explicit "today
        // 17:00" — keyword-layer dates never roll to tomorrow.
        for line in ["buy milk later", "buy milk eod", "buy milk end of day"] {
            let r = NaturalLanguageParser.parse(line, now: date(2026, 8, 9, 18, 0),
                                                calendar: .current, listNames: fixture)
            assertDate(r.dueDate, date(2026, 8, 9, 17, 0), "\(line) at 18:00 stays today 17:00")
            XCTAssertTrue(r.hasTime, "\(line) is timed")
        }
    }

    func test41InAWeekEqualsIn1Week() {
        // "in a week" (keyword) must agree with "in 1 week" (detector): both
        // noon of +7 days, all-day.
        let aWeek = parse("buy milk in a week")
        let oneWeek = parse("buy milk in 1 week")
        assertDate(aWeek.dueDate, date(2026, 8, 16, 12, 0), "in a week → +7 days, noon")
        assertDate(oneWeek.dueDate, date(2026, 8, 16, 12, 0), "in 1 week → +7 days, noon")
        XCTAssertFalse(aWeek.hasTime, "in a week is all-day")
        XCTAssertFalse(oneWeek.hasTime, "in 1 week is all-day")
    }

    func test42BangBangWithPriorityWord() {
        // Leading "!!" wins and must not leave the following priority word in
        // the title.
        let r = parse("!! high priority buy milk")
        XCTAssertEqual(r.priority, 1, "!! sets priority 1")
        XCTAssertEqual(r.title, "buy milk")
    }

    func test43BarePriorityNotInCompound() {
        // Bare priority keywords are standalone tokens only: "low-fat" keeps
        // its prefix, and "@p1" is a title token (too short for a location
        // phrase, and no list matches it), not a priority.
        let compound = parse("buy low-fat milk")
        XCTAssertEqual(compound.priority, 0, "low-fat is not a priority")
        XCTAssertEqual(compound.title, "buy low-fat milk")
        let list = parse("meet @p1")
        XCTAssertEqual(list.priority, 0, "@p1 is not a priority")
        XCTAssertNil(list.listToken)
        XCTAssertFalse(list.listMatched)
        XCTAssertNil(list.locationPhrase, "\"p1\" is too short for a location phrase")
        XCTAssertEqual(list.title, "meet @p1")
    }

    func test44TomorrowNightHasTime() {
        // "tomorrow night" keeps its clock: tomorrow 18:00, timed.
        let r = parse("buy milk tomorrow night")
        assertDate(r.dueDate, date(2026, 8, 10, 18, 0), "tomorrow night → tomorrow 18:00")
        XCTAssertTrue(r.hasTime)
    }

    func test45TrailingPunctuationStripped() {
        // Sentence punctuation left dangling by a date strip is removed too.
        for line in ["buy milk tomorrow,", "buy milk tomorrow.", "buy milk tomorrow!"] {
            let r = parse(line)
            XCTAssertEqual(r.title, "buy milk", "\(line) → clean title")
            assertDate(r.dueDate, date(2026, 8, 10, 12, 0), "\(line) due")
        }
    }

    // MARK: - Fix batch: relative dates, split date+time, token safety, noon/midnight

    func test46InDaysWithTimeAnywhere() {
        // "in 2 days" used to be ignored unless the phrase started the line.
        let r = parse("meet at 5pm in 2 days")
        assertDate(r.dueDate, date(2026, 8, 11, 17, 0), "5pm in 2 days → 8/11 17:00")
        XCTAssertTrue(r.hasTime)
        XCTAssertEqual(r.title, "meet")
    }

    func test47SplitDateBareTimeMerged() {
        // Detector can split "friday by 5pm" into a date-only and a bare-time match.
        let r = parse("pay rent friday by 5pm")
        assertDate(r.dueDate, date(2026, 8, 14, 17, 0), "friday 17:00")
        XCTAssertTrue(r.hasTime)
        XCTAssertEqual(r.title, "pay rent")
    }

    func test48TomorrowBeforeTimeMerged() {
        let r = parse("call tomorrow before 5pm")
        assertDate(r.dueDate, date(2026, 8, 10, 17, 0), "tomorrow 17:00")
        XCTAssertTrue(r.hasTime)
        XCTAssertEqual(r.title, "call")
    }

    func test49DayAfterTomorrow() {
        let r = parse("meet the day after tomorrow at 5pm")
        assertDate(r.dueDate, date(2026, 8, 11, 17, 0), "day after tomorrow = +2, time kept")
        XCTAssertTrue(r.hasTime)
        XCTAssertEqual(r.title, "meet")
    }

    func test50DayBeforeYesterday() {
        let r = parse("meet the day before yesterday")
        assertDate(r.dueDate, date(2026, 8, 7, 12, 0), "day before yesterday = −2")
        XCTAssertFalse(r.hasTime)
        XCTAssertEqual(r.title, "meet")
    }

    func test51PriorityNotInsideTagOrListToken() {
        // Bare priority words must not match inside #tag / @list tokens.
        let r = parse("buy milk #p3")
        XCTAssertEqual(r.priority, 0)
        XCTAssertEqual(r.tags, ["p3"])
        XCTAssertEqual(r.title, "buy milk")
    }

    func test52NoonKeywordRollsOver() {
        // 12:00 on the fixture day is past 12:47 → bare-clock rollover.
        let r = parse("call noon")
        assertDate(r.dueDate, date(2026, 8, 10, 12, 0), "noon past → next noon")
        XCTAssertTrue(r.hasTime)
        XCTAssertEqual(r.title, "call")
    }

    func test53MidnightKeywordRollsOver() {
        let r = parse("call midnight")
        assertDate(r.dueDate, date(2026, 8, 10, 0, 0), "midnight past → tomorrow 00:00")
        XCTAssertTrue(r.hasTime)
        XCTAssertEqual(r.title, "call")
    }

    func test54NextWeekdayTuesdayFixture() {
        // Pins the at-or-after + 7 "next X" rule from a Tuesday now.
        let rSat = parseAt("call next saturday", now: tuesdayNow)
        assertDate(rSat.dueDate, date(2026, 8, 22, 12, 0), "next saturday from Tue = +11")
        XCTAssertEqual(rSat.title, "call")
        let rMon = parseAt("call next monday", now: tuesdayNow)
        assertDate(rMon.dueDate, date(2026, 8, 24, 12, 0), "next monday from Tue = +13 (at-or-after + 7)")
        XCTAssertEqual(rMon.title, "call")
    }

    func test55TagTrailingPunctuationStripped() {
        // "#urgent." must yield the same tag as "#urgent" so chips, filter,
        // and search agree.
        XCTAssertEqual(NaturalLanguageParser.extractTags(from: "buy milk #urgent."), ["urgent"])
    }

    func test56OngoingTagPreservesDateAndTitle() {
        let r = parse("Prepare for the planning meeting Thursday #ongoing")
        XCTAssertEqual(r.title, "Prepare for the planning meeting")
        XCTAssertEqual(r.tags, ["ongoing"])
        assertDate(r.dueDate, date(2026, 8, 13, 12, 0), "Thursday due date remains intact")
    }

    func test57OngoingDetectionIsCaseInsensitiveAcrossTitleAndNotes() {
        XCTAssertTrue(NaturalLanguageParser.isOngoing(title: "Review #ONGOING", notes: nil))
        XCTAssertTrue(NaturalLanguageParser.isOngoing(title: "Review", notes: "marker #OnGoInG"))
    }

    func test58OngoingDetectionDoesNotMatchLongerToken() {
        XCTAssertFalse(NaturalLanguageParser.isOngoing(title: "Review #ongoingly", notes: nil))
    }

    func test59RemovingOngoingTagPreservesNotesContent() {
        let notes = "Project context\n#work\n#ongoing"
        XCTAssertEqual(NaturalLanguageParser.removingTag("ongoing", from: notes), "Project context\n#work")
    }
    func test60ReplacingTagPreservesPunctuationAndLineBreaks() {
        let notes = "Context #work, then #work\n#urgent"
        XCTAssertEqual(
            NaturalLanguageParser.replacingTag("work", with: "projects", in: notes),
            "Context #projects, then #projects\n#urgent"
        )
    }

    func test61ReplacingTagDoesNotMatchLongerToken() {
        XCTAssertEqual(
            NaturalLanguageParser.replacingTag("work", with: "projects", in: "#workshop #work"),
            "#workshop #projects"
        )
    }
}
