import XCTest
@testable import remr

final class SearchParserTests: XCTestCase {

    func testParseTokens() {
        let q = SearchParser.parse("!! @work #urgent fix login")
        XCTAssertTrue(q.priorityHigh)
        XCTAssertEqual(q.listTokens, ["work"])
        XCTAssertEqual(q.tags, ["urgent"])
        XCTAssertEqual(q.words, ["fix", "login"])
    }

    func testParseEmpty() {
        let q = SearchParser.parse("")
        XCTAssertEqual(q, SearchQuery())
    }

    func testMatchesTrue() {
        let q = SearchParser.parse("!! @work #urgent fix login")
        XCTAssertTrue(SearchParser.matches(query: q, calendarTitle: "Work", priority: 1,
                                           title: "fix login bug", notes: "a #urgent followup"))
    }

    func testMatchesListMismatchFails() {
        let q = SearchParser.parse("@personal")
        XCTAssertFalse(SearchParser.matches(query: q, calendarTitle: "Work", priority: 0,
                                            title: "anything", notes: nil))
    }

    func testMatchesWordMismatchFails() {
        let q = SearchParser.parse("billing")
        XCTAssertFalse(SearchParser.matches(query: q, calendarTitle: "Work", priority: 0,
                                            title: "fix login bug", notes: "urgent"))
    }

    func testMatchesPriorityFlagFails() {
        let q = SearchParser.parse("!!")
        XCTAssertFalse(SearchParser.matches(query: q, calendarTitle: "Work", priority: 5,
                                            title: "fix login bug", notes: nil))
    }

    func testMatchesNoCalendarFailsListQuery() {
        let q = SearchParser.parse("@work")
        XCTAssertFalse(SearchParser.matches(query: q, calendarTitle: nil, priority: 0,
                                            title: "fix login bug", notes: nil))
    }

    func testEmptyQueryMatchesEverything() {
        XCTAssertTrue(SearchParser.matches(query: SearchQuery(), calendarTitle: nil, priority: 0,
                                           title: "anything", notes: nil))
    }

    func testTagQueryMatchesOnlyTaggedText() {
        // `#urgent` matches the #token exactly (same rule as the chip filter),
        // not prose that merely contains the word.
        let q = SearchParser.parse("#urgent")
        XCTAssertTrue(SearchParser.matches(query: q, calendarTitle: "Work", priority: 0,
                                           title: "call #urgent", notes: nil))
        XCTAssertFalse(SearchParser.matches(query: q, calendarTitle: "Work", priority: 0,
                                            title: "an urgent matter", notes: nil))
    }

    func testTagTrailingPunctuationStripped() {
        XCTAssertEqual(NaturalLanguageParser.extractTags(from: "buy milk #urgent."), ["urgent"])
    }
}
