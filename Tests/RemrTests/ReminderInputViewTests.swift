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
}
