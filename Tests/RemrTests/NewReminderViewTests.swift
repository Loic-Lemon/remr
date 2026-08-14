import XCTest
@testable import remr

final class NewReminderViewTests: XCTestCase {

    private let lists = ["Home", "Errands", "The Office", "Groceries"]
    private let tags = ["urgent", "work", "shopping"]

    // MARK: - List (@) suggestions

    func testListPrefixSuggestsMatchingList() {
        let matches = NewReminderView.suggestionCandidates(for: "@hom", listTitles: lists, tags: tags)
        XCTAssertEqual(matches.map(\.label), ["@Home"])
    }

    func testListMatchingIsCaseInsensitive() {
        let matches = NewReminderView.suggestionCandidates(for: "@GROC", listTitles: lists, tags: tags)
        XCTAssertEqual(matches.map(\.replacement), ["@Groceries"])
    }

    func testListExactMatchIsExcluded() {
        // Accepting a suggestion leaves the full token in the field; the
        // dropdown must close instead of re-proposing the inserted item.
        XCTAssertTrue(NewReminderView.suggestionCandidates(for: "@Home", listTitles: lists, tags: tags).isEmpty)
    }

    func testMultiwordListSuggestsAndExactIsExcluded() {
        let partial = NewReminderView.suggestionCandidates(for: "@the", listTitles: lists, tags: tags)
        XCTAssertEqual(partial.map(\.label), ["@The Office"])
        XCTAssertTrue(NewReminderView.suggestionCandidates(for: "@The Office", listTitles: lists, tags: tags).isEmpty)
    }

    func testBareAtYieldsNoListSuggestions() {
        XCTAssertTrue(NewReminderView.suggestionCandidates(for: "@", listTitles: lists, tags: tags).isEmpty)
    }

    // MARK: - Tag (#) suggestions

    func testTagPrefixSuggestsMatchingTag() {
        let matches = NewReminderView.suggestionCandidates(for: "#ur", listTitles: lists, tags: tags)
        XCTAssertEqual(matches.map(\.label), ["#urgent"])
    }

    func testTagExactMatchIsExcluded() {
        XCTAssertTrue(NewReminderView.suggestionCandidates(for: "#urgent", listTitles: lists, tags: tags).isEmpty)
    }

    func testBareHashYieldsNoTagSuggestions() {
        XCTAssertTrue(NewReminderView.suggestionCandidates(for: "#", listTitles: lists, tags: tags).isEmpty)
    }

    // MARK: - Date / priority keyword suggestions

    func testKeywordPrefixSuggestsDatesAndPriorities() {
        let matches = NewReminderView.suggestionCandidates(for: "tom", listTitles: lists, tags: tags)
        XCTAssertEqual(matches.map(\.replacement), ["tomorrow"])
        let priorityMatches = NewReminderView.suggestionCandidates(for: "med", listTitles: lists, tags: tags)
        XCTAssertEqual(priorityMatches.map(\.replacement), ["medium"])
    }

    func testKeywordExactMatchIsExcluded() {
        XCTAssertTrue(NewReminderView.suggestionCandidates(for: "tomorrow", listTitles: lists, tags: tags).isEmpty)
        XCTAssertTrue(NewReminderView.suggestionCandidates(for: "high", listTitles: lists, tags: tags).isEmpty)
    }

    func testSingleCharacterTokenYieldsNoKeywordSuggestions() {
        XCTAssertTrue(NewReminderView.suggestionCandidates(for: "t", listTitles: lists, tags: tags).isEmpty)
    }

    // MARK: - Boundaries

    func testEmptyTokenYieldsNothing() {
        XCTAssertTrue(NewReminderView.suggestionCandidates(for: "", listTitles: lists, tags: tags).isEmpty)
    }

    func testCandidatesAreDeduplicated() {
        let duplicates = ["Home", "home", "HOME"]
        let matches = NewReminderView.suggestionCandidates(for: "@ho", listTitles: duplicates, tags: [])
        XCTAssertEqual(matches.map(\.label), ["@Home"])
    }
}
