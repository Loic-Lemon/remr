import XCTest
@testable import remr

final class ReminderInputViewTests: XCTestCase {

    func testPlainReturnSubmits() {
        let textView = EnterSubmitTextView()
        textView.string = "buy milk"
        var fired = false
        textView.onSubmit = { fired = true }

        textView.insertNewline(nil)

        XCTAssertTrue(fired)
        XCTAssertFalse(textView.string.contains("\n"))
    }

    func testNoopOnMoveDownDoesNotBlockSubmit() {
        // Regression: the wiring always assigns onMoveDown (a no-op when the
        // field has no move-down action, as in the notes field). Dispatch
        // keys off movesDownOnReturn, not closure nil-ness, or Return would
        // dead-key in the notes field.
        let textView = EnterSubmitTextView()
        textView.string = "call back"
        textView.onMoveDown = {}
        var fired = false
        textView.onSubmit = { fired = true }

        textView.insertNewline(nil)

        XCTAssertTrue(fired)
        XCTAssertFalse(textView.string.contains("\n"))
    }

    func testShiftReturnWithNoopOnMoveDownInsertsNewline() {
        let textView = EnterSubmitTextView()
        textView.string = "line one"
        textView.onMoveDown = {}
        var fired = false
        textView.onSubmit = { fired = true }
        textView.modifierFlagsOverride = .shift

        textView.insertNewline(nil)

        XCTAssertFalse(fired)
        XCTAssertEqual(textView.string, "line one\n")
    }

    func testMovesDownOnReturnRoutesToOnMoveDown() {
        // Single-line title field: Return moves down, never submits.
        let textView = EnterSubmitTextView()
        textView.movesDownOnReturn = true
        var moved = false
        textView.onMoveDown = { moved = true }
        var fired = false
        textView.onSubmit = { fired = true }

        textView.insertNewline(nil)

        XCTAssertTrue(moved)
        XCTAssertFalse(fired)
    }

    func testShiftReturnInsertsNewline() {
        let textView = EnterSubmitTextView()
        textView.string = "buy milk"
        var fired = false
        textView.onSubmit = { fired = true }
        textView.modifierFlagsOverride = .shift

        textView.insertNewline(nil)

        XCTAssertFalse(fired)
        XCTAssertEqual(textView.string, "buy milk\n")
    }

    func testTabWithNoDropdownFiresOnFocusForwardAndInsertsNoTab() {
        let textView = EnterSubmitTextView()
        textView.string = "buy milk"
        var fired = false
        textView.onFocusForward = { fired = true }

        textView.insertTab(nil)

        XCTAssertTrue(fired)
        XCTAssertEqual(textView.string, "buy milk")
    }

    func testTabWithDropdownActiveFiresOnMoveDown() {
        let textView = EnterSubmitTextView()
        textView.dropdownActive = true
        var movedDown = false
        textView.onMoveDown = { movedDown = true }
        var focusForwarded = false
        textView.onFocusForward = { focusForwarded = true }

        textView.insertTab(nil)

        XCTAssertTrue(movedDown)
        XCTAssertFalse(focusForwarded)
    }

    func testInsertBacktabFiresOnFocusBack() {
        let textView = EnterSubmitTextView()
        var fired = false
        textView.onFocusBack = { fired = true }

        textView.insertBacktab(nil)

        XCTAssertTrue(fired)
    }

    func testCancelOperationWithNoDropdownFiresOnEscape() {
        let textView = EnterSubmitTextView()
        var dismissed = false
        textView.onDismiss = { dismissed = true }
        var escaped = false
        textView.onEscape = { escaped = true }

        textView.cancelOperation(nil)

        XCTAssertTrue(escaped)
        XCTAssertFalse(dismissed)
    }

    func testListCompletionContextScansMultiwordQuery() {
        let textView = EnterSubmitTextView()
        textView.string = "buy @the o"
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))

        XCTAssertEqual(textView.currentCompletionContext(), CompletionContext(
            text: "@the o", range: NSRange(location: 4, length: 6)))
    }

    func testCompletionRangeUsesUTF16Offsets() {
        let textView = EnterSubmitTextView()
        textView.string = "📝 @the o"
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))

        XCTAssertEqual(textView.currentCompletionContext(), CompletionContext(
            text: "@the o", range: NSRange(location: 3, length: 6)))
    }

    func testCompletedMultiwordListLeavesTrailingSpaceOutsideRange() {
        let textView = EnterSubmitTextView()
        textView.string = "@home depot "
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
        let context = textView.currentCompletionContext()

        XCTAssertEqual(context.text, "@home depot")
        XCTAssertEqual(context.range, NSRange(location: 0, length: 11))
        textView.replaceCurrentCompletion(with: "@Home Depot", in: context.range)

        XCTAssertEqual(textView.string, "@Home Depot ")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 11, length: 0))
    }

    func testCompletionReplacementUsesCapturedRangeWhenCaretIsInMiddle() {
        let textView = EnterSubmitTextView()
        textView.string = "before @the office"
        textView.setSelectedRange(NSRange(location: 11, length: 0))
        let context = textView.currentCompletionContext()

        XCTAssertEqual(context.text, "@the")
        textView.replaceCurrentCompletion(with: "@The Office", in: context.range)

        XCTAssertEqual(textView.string, "before @The Office office")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 18, length: 0))
    }

    func testTagCompletionRemainsWhitespaceBounded() {
        let textView = EnterSubmitTextView()
        textView.string = "buy #gro"
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))

        XCTAssertEqual(textView.currentCompletionContext(), CompletionContext(
            text: "#gro", range: NSRange(location: 4, length: 4)))
    }

    func testEmailAtDoesNotTriggerListCompletion() {
        let textView = EnterSubmitTextView()
        textView.string = "email@example.com"
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))

        XCTAssertEqual(textView.currentCompletionContext(), CompletionContext(
            text: "email@example.com", range: NSRange(location: 0, length: 17)))
    }
}
