import Foundation
import XCTest
@testable import remr

final class BulkReminderPreviewTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testParseBulkOmitsBlankLinesAndPreservesOrder() {
        let parsed = NaturalLanguageParser.parseBulk("first\n\n  \nsecond\nthird", now: fixedDate)
        let rows = BulkReminderPreviewState.rows(from: parsed) { token in
            token.caseInsensitiveCompare("Home") == .orderedSame ? ("home-id", "Home") : nil
        }

        XCTAssertEqual(rows.map { $0.draft.title }, ["first", "second", "third"])
        XCTAssertEqual(rows.map { $0.draft.rawInput ?? "" }, ["first", "second", "third"])
        XCTAssertEqual(Set(rows.map(\.id)).count, 3)
        XCTAssertEqual(rows.map(\.state), [.ready, .ready, .ready])
    }

    func testSelectionDefaultsKeepEmptyTitleOffAndUnknownListOn() {
        let parsed = NaturalLanguageParser.parseBulk("tomorrow\n@unknown list task\nordinary", now: fixedDate,
                                                       listNames: ["Home"])
        let rows = BulkReminderPreviewState.rows(from: parsed) { _ in nil }

        XCTAssertEqual(rows.count, 3)
        XCTAssertFalse(rows[0].selected)
        XCTAssertTrue(rows[0].draft.diagnostics.contains(.emptyTitle))
        XCTAssertTrue(rows[1].selected)
        XCTAssertTrue(rows[1].draft.diagnostics.contains { diagnostic in
            if case .unmatchedList("unknown") = diagnostic { return true }
            return false
        })
        XCTAssertTrue(rows[2].selected)
    }

    func testTitleReparsePreservesRowIDAndNotes() {
        let parsed = NaturalLanguageParser.parseBulk("old title", now: fixedDate, listNames: ["Home"])
        var state = BulkReminderPreviewState(rows: BulkReminderPreviewState.rows(from: parsed) { _ in nil })
        state.rows[0].draft.notes = "Keep this note"
        let id = state.rows[0].id

        state.reparseTitle(at: 0,
                           title: "new title tomorrow @Home",
                           now: fixedDate,
                           calendar: calendar,
                           listNames: ["Home"]) { token in
            token == "Home" ? ("home-id", "Home") : nil
        }

        XCTAssertEqual(state.rows[0].id, id)
        XCTAssertEqual(state.rows[0].draft.id, id)
        XCTAssertEqual(state.rows[0].draft.title, "new title")
        XCTAssertEqual(state.rows[0].draft.notes, "Keep this note")
        XCTAssertEqual(state.rows[0].draft.calendarIdentifier, "home-id")
        XCTAssertEqual(state.rows[0].state, .ready)
    }

    func testPartialFailureAndRetryOnlyChangeTheirOwnRows() {
        let parsed = NaturalLanguageParser.parseBulk("one\ntwo\nthree", now: fixedDate)
        var state = BulkReminderPreviewState(rows: BulkReminderPreviewState.rows(from: parsed) { _ in nil })
        XCTAssertEqual(state.selectedCreatableIndices, [0, 1, 2])

        state.markCreated(at: 0)
        state.markFailed(at: 1, message: "temporary failure")
        XCTAssertEqual(state.rows[0].state, .created)
        XCTAssertEqual(state.rows[1].state, .failed("temporary failure"))
        XCTAssertEqual(state.rows[2].state, .ready)
        XCTAssertTrue(state.canCreateSelected)

        state.markReady(at: 1)
        XCTAssertEqual(state.rows[1].state, .ready)
        XCTAssertEqual(state.rows[0].state, .created)
        XCTAssertEqual(state.rows[2].state, .ready)
        XCTAssertFalse(state.rows[0].selectedCreatable)
    }

    func testCreatedRowsBlockDuplicateCreateButDoneAppearsAfterSuccess() {
        let parsed = NaturalLanguageParser.parseBulk("one\ntwo", now: fixedDate)
        var state = BulkReminderPreviewState(rows: BulkReminderPreviewState.rows(from: parsed) { _ in nil })
        XCTAssertTrue(state.canCreateSelected)
        state.markCreated(at: 0)
        XCTAssertTrue(state.hasCreatedRow)
        XCTAssertTrue(state.canCreateSelected)
        state.rows[0].selected = true
        XCTAssertFalse(state.canCreateSelected)
        state.rows[0].selected = false
        state.rows[1].selected = false
        XCTAssertFalse(state.canCreateSelected)
    }

    private var fixedDate: Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 10))!
    }
}

private extension BulkReminderRow {
    var selectedCreatable: Bool {
        selected && !draft.diagnostics.contains(.emptyTitle) && state != .created
    }
}
