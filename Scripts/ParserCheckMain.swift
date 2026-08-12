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

    // Fixed `now` for the weekday cases: 2026-08-11 13:26 local (Tuesday).
    var tuesComps = DateComponents()
    tuesComps.year = 2026
    tuesComps.month = 8
    tuesComps.day = 11
    tuesComps.hour = 13
    tuesComps.minute = 26
    let tuesNow = Calendar.current.date(from: tuesComps)!

    let fixture = ["Home", "Work", "Groceries", "AH"]

    func parse(_ line: String, lists: [String]? = nil) -> ParsedReminder {
        NaturalLanguageParser.parse(line, now: now, calendar: .current, listNames: lists ?? fixture)
    }

    func parseAt(_ line: String, now: Date, lists: [String]? = nil) -> ParsedReminder {
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
        check(r.diagnostics.isEmpty, "10 diagnostics empty for matched list")
    }

    // 11. unmatched list (whole-line @ stays in the title)
    do {
        let r = parse("@unknown list task")
        check(r.listToken == nil, "11 no list token")
        check(!r.listMatched, "11 unmatched")
        check(r.locationPhrase == nil, "11 no location (line-start @)")
        checkEqual(r.diagnostics, [.unmatchedList("unknown")], "11 unmatched-list diagnostic")
        checkEqual(r.title, "@unknown list task", "11 title")
    }

    // 11b. @ is list-only: an unmatched @token stays in the title with a
    // diagnostic — locations use the & prefix now, not @
    do {
        let r = parse("buy milk @the office")
        check(r.locationPhrase == nil, "11b no location from @")
        check(r.listToken == nil, "11b no list token")
        checkEqual(r.diagnostics, [.unmatchedList("the")], "11b unmatched-list diagnostic")
        checkEqual(r.title, "buy milk @the office", "11b title")
    }

    // 11c. & — the explicit location prefix
    do {
        let r = parse("buy milk &the office")
        checkEqual(r.locationPhrase, "the office", "11c location")
        checkEqual(r.title, "buy milk", "11c title")
        check(r.diagnostics.isEmpty, "11c diagnostics empty")
        let spaced = parse("buy milk & the office")
        checkEqual(spaced.locationPhrase, "the office", "11c location (space after &)")
        checkEqual(spaced.title, "buy milk", "11c title (space after &)")
    }

    // 11d. & mid-sentence stops at the clause boundary
    do {
        let r = parse("i need to do this &home")
        checkEqual(r.locationPhrase, "home", "11d location")
        checkEqual(r.title, "i need to do this", "11d title")
    }

    // 11e. & at line start, and & with a here-phrase
    do {
        let r = parse("&the office i need milk")
        checkEqual(r.locationPhrase, "the office", "11e location")
        checkEqual(r.title, "i need milk", "11e title")
        let here = parse("meet &here")
        checkEqual(here.locationPhrase, "here", "11e here location")
        checkEqual(here.title, "meet", "11e here title")
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

    // 13b. mid-sentence "at" location stops at the clause boundary
    do {
        let r = parse("at home i need to do this")
        checkEqual(r.locationPhrase, "home", "13b location")
        checkEqual(r.title, "i need to do this", "13b title")
    }

    // 13c. at + dash separator ("--" stays in the title as the sentence break)
    do {
        let r = parse("fix the sink at home -- i need to do this")
        checkEqual(r.locationPhrase, "home", "13c location")
        checkEqual(r.title, "fix the sink -- i need to do this", "13c title")
    }

    // 13d. at + em dash separator
    do {
        let r = parse("fix the sink at home — need milk")
        checkEqual(r.locationPhrase, "home", "13d location")
        checkEqual(r.title, "fix the sink — need milk", "13d title")
    }

    // 13e. & location mid-sentence stops at the clause boundary
    do {
        let r = parse("buy milk &the office and grab the mail")
        checkEqual(r.locationPhrase, "the office", "13e location")
        checkEqual(r.title, "buy milk and grab the mail", "13e title")
    }

    // 13f. capitalized "and" is a place join, not a clause ("5th and Main")
    do {
        let r = parse("meet at 5th and Main")
        checkEqual(r.locationPhrase, "5th and Main", "13f location")
        checkEqual(r.title, "meet", "13f title")
    }

    // 13g. "my location" keeps "my" (here-phrase)
    do {
        let r = parse("pick up laundry at my location")
        checkEqual(r.locationPhrase, "my location", "13g location")
        checkEqual(r.title, "pick up laundry", "13g title")
    }

    // 14. quoted & location is verbatim — stop words inside stay
    do {
        let r = parse("meet &\"the office and grill\"")
        checkEqual(r.locationPhrase, "the office and grill", "14 location")
        checkEqual(r.title, "meet", "14 title")
    }

    // 15. quoted at location
    do {
        let r = parse("lunch at \"Salt and Straw\"")
        checkEqual(r.locationPhrase, "Salt and Straw", "15 location")
        checkEqual(r.title, "lunch", "15 title")
    }

    // 16. quoted mid-sentence keeps everything after the quote in the title
    do {
        let r = parse("&\"the office and grill\" i need milk")
        checkEqual(r.locationPhrase, "the office and grill", "16 location")
        checkEqual(r.title, "i need milk", "16 title")
    }

    // 17. unquoted lowercase "and" still splits (documented boundary behavior)
    do {
        let r = parse("meet &the office and grill")
        checkEqual(r.locationPhrase, "the office", "17 location")
        checkEqual(r.title, "meet and grill", "17 title")
    }

    // 18. unquoted capitalized "and" is a place join
    do {
        let r = parse("meet &The Office and Main")
        checkEqual(r.locationPhrase, "The Office and Main", "18 location")
        checkEqual(r.title, "meet", "18 title")
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
        checkEqual(r.diagnostics, [.emptyTitle], "15 empty-title diagnostic")
    }

    // 15b. tag-only line is invalid with an empty-title diagnostic
    do {
        let r = parse("#groceries")
        check(r.isInvalid, "15b isInvalid")
        checkEqual(r.diagnostics, [.emptyTitle], "15b empty-title diagnostic")
    }

    // 15c. email addresses do not create list warnings
    do {
        let r = parse("Email john@home.example about the party")
        check(r.listToken == nil && !r.listMatched, "15c email is not a list")
        checkEqual(r.title, "Email john@home.example about the party", "15c email title")
        check(r.diagnostics.isEmpty, "15c email diagnostics empty")
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
                                   title: "fix login bug", notes: "a #urgent followup"), "search matches: all")
        let qList = SearchParser.parse("@personal")
        check(!SearchParser.matches(query: qList, calendarTitle: "Work", priority: 0,
                                    title: "anything", notes: nil), "search matches: @personal fails")
        let qWord = SearchParser.parse("billing")
        check(!SearchParser.matches(query: qWord, calendarTitle: "Work", priority: 0,
                                    title: "fix login bug", notes: "urgent"), "search matches: billing fails")
        check(SearchParser.matches(query: SearchQuery(), calendarTitle: nil, priority: 0,
                                   title: "anything", notes: nil), "search matches: empty query")
    }

    // containsTag (tag filter rule)
    do {
        check(NaturalLanguageParser.containsTag("groceries", in: "buy milk #groceries"), "containsTag: exact token")
        check(NaturalLanguageParser.containsTag("groceries", in: "buy milk #groceries #urgent"), "containsTag: among several")
        check(NaturalLanguageParser.containsTag("urgent", in: "call #URGENT"), "containsTag: case-insensitive (input)")
        check(NaturalLanguageParser.containsTag("Urgent", in: "call #urgent"), "containsTag: case-insensitive (filter)")
        check(!NaturalLanguageParser.containsTag("urgent", in: "an urgent matter"), "containsTag: prose without # never matches")
        check(!NaturalLanguageParser.containsTag("groceries", in: "buy groceries"), "containsTag: plain word never matches")
        check(!NaturalLanguageParser.containsTag("milk", in: "buy #milkman"), "containsTag: substring token never matches")
        check(!NaturalLanguageParser.containsTag("work", in: "no tags here"), "containsTag: empty of tags")
        check(!NaturalLanguageParser.containsTag("work", in: ""), "containsTag: empty input")
    }

    // 21. next week → +7 days noon, all-day
    do {
        let r = parse("buy milk next week")
        checkDate(r.dueDate, date(2026, 8, 16, 12, 0), "21 due (next week → +7 days noon)")
        check(!r.hasTime, "21 hasTime false (all-day)")
        checkEqual(r.title, "buy milk", "21 title")
        check(!r.isInvalid, "21 valid")
    }

    // 22. this week → last day of the current week, noon
    do {
        let r = parse("buy milk this week")
        let weekEnd = Calendar.current.dateInterval(of: .weekOfYear, for: now)!.end
        let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: weekEnd)!
        let expected = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: lastDay)!
        checkDate(r.dueDate, expected, "22 due (this week → last day of week, noon)")
        check(!r.hasTime, "22 hasTime false (all-day)")
    }

    // 23. tonight after 18:00 stays today
    do {
        var c = DateComponents()
        c.year = 2026; c.month = 8; c.day = 9; c.hour = 19; c.minute = 0
        let lateNow = Calendar.current.date(from: c)!
        let r = NaturalLanguageParser.parse("clean kitchen tonight", now: lateNow, calendar: .current, listNames: fixture)
        checkDate(r.dueDate, date(2026, 8, 9, 18, 0), "23 due (tonight at 19:00 stays today)")
        check(r.hasTime, "23 hasTime")
    }

    // 24. later/eod/end of day after 17:00 stays today
    do {
        var c = DateComponents()
        c.year = 2026; c.month = 8; c.day = 9; c.hour = 18; c.minute = 0
        let lateNow = Calendar.current.date(from: c)!
        for line in ["buy milk later", "buy milk eod", "buy milk end of day"] {
            let r = NaturalLanguageParser.parse(line, now: lateNow, calendar: .current, listNames: fixture)
            checkDate(r.dueDate, date(2026, 8, 9, 17, 0), "24 due (\(line) at 18:00 stays today 17:00)")
            check(r.hasTime, "24 hasTime (\(line))")
        }
    }

    // 25. in a week == in 1 week
    do {
        let aWeek = parse("buy milk in a week")
        let oneWeek = parse("buy milk in 1 week")
        checkDate(aWeek.dueDate, date(2026, 8, 16, 12, 0), "25 due (in a week → +7 days noon)")
        checkDate(oneWeek.dueDate, date(2026, 8, 16, 12, 0), "25 due (in 1 week → +7 days noon)")
        check(!aWeek.hasTime, "25 hasTime false (in a week all-day)")
        check(!oneWeek.hasTime, "25 hasTime false (in 1 week all-day)")
    }

    // 26. !! with a following priority word
    do {
        let r = parse("!! high priority buy milk")
        checkEqual(r.priority, 1, "26 priority (!! wins)")
        checkEqual(r.title, "buy milk", "26 title")
    }

    // 27. bare priority not in compounds
    do {
        let compound = parse("buy low-fat milk")
        checkEqual(compound.priority, 0, "27 priority (low-fat not a priority)")
        checkEqual(compound.title, "buy low-fat milk", "27 title intact")
        let list = parse("meet @p1")
        checkEqual(list.priority, 0, "27 priority (@p1 not a priority)")
        check(list.listToken == nil, "27 no list token")
        check(!list.listMatched, "27 list unmatched")
        check(list.locationPhrase == nil, "27 no location (\"p1\" too short)")
        checkEqual(list.title, "meet @p1", "27 title")
    }

    // 28. tomorrow night keeps its time
    do {
        let r = parse("buy milk tomorrow night")
        checkDate(r.dueDate, date(2026, 8, 10, 18, 0), "28 due (tomorrow night → 18:00)")
        check(r.hasTime, "28 hasTime")
    }

    // 29. trailing punctuation stripped with the date
    do {
        for line in ["buy milk tomorrow,", "buy milk tomorrow.", "buy milk tomorrow!"] {
            let r = parse(line)
            checkEqual(r.title, "buy milk", "29 title (\(line))")
            checkDate(r.dueDate, date(2026, 8, 10, 12, 0), "29 due (\(line))")
        }
    }

    // 30. "in 2 days" with a clock time, phrase mid-line
    do {
        let r = parse("meet at 5pm in 2 days")
        checkDate(r.dueDate, date(2026, 8, 11, 17, 0), "30 due (5pm in 2 days → 8/11 17:00)")
        check(r.hasTime, "30 hasTime")
        checkEqual(r.title, "meet", "30 title")
    }

    // 31. split date + bare time merged ("friday by 5pm")
    do {
        let r = parse("pay rent friday by 5pm")
        checkDate(r.dueDate, date(2026, 8, 14, 17, 0), "31 due (friday 17:00)")
        check(r.hasTime, "31 hasTime")
        checkEqual(r.title, "pay rent", "31 title")
    }

    // 32. "tomorrow before 5pm" keeps the time
    do {
        let r = parse("call tomorrow before 5pm")
        checkDate(r.dueDate, date(2026, 8, 10, 17, 0), "32 due (tomorrow 17:00)")
        check(r.hasTime, "32 hasTime")
        checkEqual(r.title, "call", "32 title")
    }

    // 33. day after tomorrow = +2 (with time)
    do {
        let r = parse("meet the day after tomorrow at 5pm")
        checkDate(r.dueDate, date(2026, 8, 11, 17, 0), "33 due (day after tomorrow 17:00)")
        check(r.hasTime, "33 hasTime")
        checkEqual(r.title, "meet", "33 title")
    }

    // 34. day before yesterday = −2
    do {
        let r = parse("meet the day before yesterday")
        checkDate(r.dueDate, date(2026, 8, 7, 12, 0), "34 due (day before yesterday)")
        check(!r.hasTime, "34 hasTime false")
        checkEqual(r.title, "meet", "34 title")
    }

    // 35. priority words inside #tag tokens are not priorities
    do {
        let r = parse("buy milk #p3")
        checkEqual(r.priority, 0, "35 priority (token-internal p3)")
        checkEqual(r.tags, ["p3"], "35 tags")
        checkEqual(r.title, "buy milk", "35 title")
    }

    // 36. noon keyword (rolls when past)
    do {
        let r = parse("call noon")
        checkDate(r.dueDate, date(2026, 8, 10, 12, 0), "36 due (noon past → next noon)")
        check(r.hasTime, "36 hasTime")
        checkEqual(r.title, "call", "36 title")
    }

    // 37. midnight keyword (rolls when past)
    do {
        let r = parse("call midnight")
        checkDate(r.dueDate, date(2026, 8, 10, 0, 0), "37 due (midnight past → tomorrow 00:00)")
        check(r.hasTime, "37 hasTime")
        checkEqual(r.title, "call", "37 title")
    }

    // 38. "next X" from a Tuesday now (at-or-after + 7)
    do {
        let rSat = parseAt("call next saturday", now: tuesNow)
        checkDate(rSat.dueDate, date(2026, 8, 22, 12, 0), "38 due (next saturday from Tue = +11)")
        checkEqual(rSat.title, "call", "38 title")
        let rMon = parseAt("call next monday", now: tuesNow)
        checkDate(rMon.dueDate, date(2026, 8, 24, 12, 0), "38 due (next monday from Tue = +13)")
        checkEqual(rMon.title, "call", "38 title monday")
    }

    // 39. #tag search is token-exact; trailing punctuation stripped
    do {
        let q = SearchParser.parse("#urgent")
        check(SearchParser.matches(query: q, calendarTitle: "Work", priority: 0,
                                   title: "call #urgent", notes: nil), "39 search: #urgent token matches")
        check(!SearchParser.matches(query: q, calendarTitle: "Work", priority: 0,
                                    title: "an urgent matter", notes: nil), "39 search: prose #urgent never matches")
        checkEqual(NaturalLanguageParser.extractTags(from: "buy milk #urgent."), ["urgent"], "39 extractTags: punctuation stripped")
    }

    // 40. #ongoing preserves title, tags, and the real Thursday due date
    do {
        let r = parse("Prepare for the planning meeting Thursday #ongoing")
        checkEqual(r.title, "Prepare for the planning meeting", "40 title")
        checkEqual(r.tags, ["ongoing"], "40 tags")
        checkDate(r.dueDate, date(2026, 8, 13, 12, 0), "40 due (Thursday remains intact)")
    }

    // 41. #ongoing detection is case-insensitive across title and notes
    do {
        check(NaturalLanguageParser.isOngoing(title: "Review #ONGOING", notes: nil), "41 ongoing in title")
        check(NaturalLanguageParser.isOngoing(title: "Review", notes: "marker #OnGoInG"), "41 ongoing in notes")
    }

    // 42. #ongoingly is not the ongoing marker
    do {
        check(!NaturalLanguageParser.isOngoing(title: "Review #ongoingly", notes: nil), "42 longer token does not match")
    }

    // 43. removing a trailing marker preserves prose, line breaks, and #work
    do {
        let notes = "Project context\n#work\n#ongoing"
        checkEqual(NaturalLanguageParser.removingTag("ongoing", from: notes), "Project context\n#work", "43 notes removal")
    }

    print("Parser check: \(passed) passed, \(failures) failed")
    exit(failures > 0 ? 1 : 0)

    }
}
