// Parser verification harness — XCTest-free replacement for `swift test`.
//
// CommandLineTools (no Xcode) ships no public XCTest.framework, so the
// XCTest-based tests in Tests/remrTests cannot compile here. This
// file compiles together with the parser sources and asserts the same
// cases; exit code 0 = all pass.
//
// Run via: Scripts/parser-check.sh

import Foundation

@main
struct ParserCheck {
    static func main() {

    var passed = 0
    var failures = 0

    func check(_ condition: Bool, _ name: String) {
        if condition { passed += 1 } else { failures += 1; print("FAIL: \(name)") }
    }

    func checkEqual<T: Equatable>(_ a: T, _ b: T, _ name: String) {
        check(a == b, "\(name) — expected \(b), got \(a)")
    }

    func checkDate(_ actual: Date?, _ expected: Date, _ name: String) {
        guard let actual else {
            check(false, "\(name) — expected \(expected), got nil")
            return
        }
        check(abs(actual.timeIntervalSince1970 - expected.timeIntervalSince1970) < 60,
              "\(name) — expected \(expected), got \(actual)")
    }

    // Fixed `now`: 2026-08-09 12:47 local (Sunday).
    var nowComps = DateComponents()
    nowComps.year = 2026
    nowComps.month = 8
    nowComps.day = 9
    nowComps.hour = 12
    nowComps.minute = 47
    let now = Calendar.current.date(from: nowComps)!

    let fixture = ["Home", "Work", "Groceries", "AH"]

    func parse(_ line: String, lists: [String]? = nil) -> ParsedReminder {
        NaturalLanguageParser.parse(line, now: now, calendar: .current, listNames: lists ?? fixture)
    }

    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = hour
        c.minute = minute
        return Calendar.current.date(from: c)!
    }

    // 1. eod + @list
    do {
        let r = parse("Take out the trash before end of day @home")
        checkEqual(r.title, "Take out the trash", "1 title")
        checkEqual(r.listToken, "home", "1 list token")
        check(r.listMatched, "1 list matched")
        checkDate(r.dueDate, date(2026, 8, 9, 17, 0), "1 due (eod → today 17:00)")
        check(r.hasTime, "1 hasTime")
        check(!r.isInvalid, "1 valid")
    }

    // 2. tomorrow 5pm
    do {
        let r = parse("Call mom tomorrow 5pm")
        checkDate(r.dueDate, date(2026, 8, 10, 17, 0), "2 due")
        check(r.hasTime, "2 hasTime")
        checkEqual(r.title, "Call mom", "2 title")
    }

    // 3. in 3 hours (detector gap → keyword)
    do {
        let r = parse("Buy milk in 3 hours")
        checkDate(r.dueDate, now.addingTimeInterval(3 * 3600), "3 due (now + 3h)")
        check(r.hasTime, "3 hasTime (keyword)")
        checkEqual(r.title, "Buy milk", "3 title")
    }

    // 4. march 15, date-only
    do {
        let r = parse("Pay rent on march 15")
        checkDate(r.dueDate, date(2027, 3, 15, 12, 0), "4 due")
        check(!r.hasTime, "4 hasTime false (all-day)")
        checkEqual(r.title, "Pay rent", "4 title")
    }

    // 5. by friday
    do {
        let r = parse("Submit report by friday")
        checkDate(r.dueDate, date(2026, 8, 14, 12, 0), "5 due (this Friday)")
        check(!r.hasTime, "5 hasTime false")
        checkEqual(r.title, "Submit report", "5 title")
    }

    // 6. bare time rollover
    do {
        let r = parse("Water plants at 10am")
        checkDate(r.dueDate, date(2026, 8, 10, 10, 0), "6 due (tomorrow 10:00 rollover)")
        check(r.hasTime, "6 hasTime")
        checkEqual(r.title, "Water plants", "6 title")
    }

    // 7. !! prefix
    do {
        let r = parse("!! urgent meeting")
        checkEqual(r.priority, 1, "7 priority")
        checkEqual(r.title, "urgent meeting", "7 title")
    }

    // 8. low priority keyword
    do {
        let r = parse("low priority cleanup")
        checkEqual(r.priority, 9, "8 priority")
        checkEqual(r.title, "cleanup", "8 title")
    }

    // 9. @AH
    do {
        let r = parse("Groceries @AH")
        checkEqual(r.listToken, "AH", "9 list token")
        check(r.listMatched, "9 list matched")
        checkEqual(r.title, "Groceries", "9 title")
    }

    // 10. two-word list token
    do {
        let r = NaturalLanguageParser.parse("@home depot shopping", now: now, calendar: .current, listNames: ["Home Depot"])
        checkEqual(r.listToken, "home depot", "10 list token")
        check(r.listMatched, "10 list matched")
        checkEqual(r.title, "shopping", "10 title")
    }

    // 11. unmatched list
    do {
        let r = parse("@unknown list task")
        checkEqual(r.listToken, "unknown", "11 list token")
        check(!r.listMatched, "11 unmatched")
        checkEqual(r.title, "list task", "11 title")
    }

    // 12. address location
    do {
        let r = parse("Pick up package at 1 Apple Park Way, Cupertino CA 95014")
        checkEqual(r.locationPhrase, "1 Apple Park Way, Cupertino CA 95014", "12 location")
        checkEqual(r.title, "Pick up package", "12 title")
    }

    // 13. trailing at-phrase location
    do {
        let r = parse("Meet John at the office")
        checkEqual(r.locationPhrase, "the office", "13 location")
        checkEqual(r.title, "Meet John", "13 title")
    }

    // 14. no tokens
    do {
        let r = parse("Buy flowers for mom")
        checkEqual(r.title, "Buy flowers for mom", "14 title")
        check(r.listToken == nil && r.dueDate == nil && r.priority == 0 && r.locationPhrase == nil,
              "14 all tokens nil")
        check(!r.isInvalid, "14 valid")
    }

    // 15. date-only line invalid
    do {
        let r = parse("tomorrow")
        check(r.isInvalid, "15 isInvalid")
        checkDate(r.dueDate, date(2026, 8, 10, 12, 0), "15 due")
    }

    // 16. multiple dates
    do {
        let r = parse("call john tomorrow at 5pm then email on friday")
        checkDate(r.dueDate, date(2026, 8, 10, 17, 0), "16 due (first match)")
        checkEqual(r.title, "call john then email", "16 title")
    }

    // 17. leading connector stripped
    do {
        let r = parse("at 5pm dinner")
        checkDate(r.dueDate, date(2026, 8, 9, 17, 0), "17 due")
        checkEqual(r.title, "dinner", "17 title")
    }

    // 18. in 2 days — detector wins over keyword
    do {
        let r = parse("in 2 days")
        checkDate(r.dueDate, date(2026, 8, 11, 12, 0), "18 due (detector)")
        check(!r.hasTime, "18 hasTime false (no double-fire)")
        check(r.isInvalid, "18 isInvalid (whole line stripped)")
    }

    // 19. tonight
    do {
        let r = parse("clean kitchen tonight")
        checkDate(r.dueDate, date(2026, 8, 9, 18, 0), "19 due")
        check(r.hasTime, "19 hasTime")
    }

    // 20. parseBulk skips empty lines
    do {
        let items = NaturalLanguageParser.parseBulk("a\n\nb", now: now, calendar: .current, listNames: fixture)
        checkEqual(items.count, 2, "20 count")
        checkEqual(items.map(\.original), ["a", "b"], "20 originals")
    }

    // Search parser
    do {
        let q = SearchParser.parse("!! @work #urgent fix login")
        check(q.priorityHigh, "search parse: priorityHigh")
        checkEqual(q.listTokens, ["work"], "search parse: listTokens")
        checkEqual(q.tags, ["urgent"], "search parse: tags")
        checkEqual(q.words, ["fix", "login"], "search parse: words")
        check(SearchParser.matches(query: q, calendarTitle: "Work", priority: 1,
                                   title: "fix login bug", notes: "urgent"), "search matches: all")
        let qList = SearchParser.parse("@personal")
        check(!SearchParser.matches(query: qList, calendarTitle: "Work", priority: 0,
                                    title: "anything", notes: nil), "search matches: @personal fails")
        let qWord = SearchParser.parse("billing")
        check(!SearchParser.matches(query: qWord, calendarTitle: "Work", priority: 0,
                                    title: "fix login bug", notes: "urgent"), "search matches: billing fails")
        check(SearchParser.matches(query: SearchQuery(), calendarTitle: nil, priority: 0,
                                   title: "anything", notes: nil), "search matches: empty query")
    }

    print("Parser check: \(passed) passed, \(failures) failed")
    exit(failures > 0 ? 1 : 0)

    }
}
