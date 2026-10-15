import XCTest
@testable import remr

final class ShortcutFlowLayoutTests: XCTestCase {
    func testLongDraftStaysWithinNarrowCardAndPreservesEveryKey() {
        let sizes = (0..<25).map { CGSize(width: $0.isMultiple(of: 3) ? 70 : 36, height: 25) }
        for width in [CGFloat(220), 280, 320, 500] {
            let frames = ShortcutFlowLayout.frames(for: sizes, width: width)
            XCTAssertEqual(frames.count, sizes.count)
            XCTAssertTrue(frames.allSatisfy { $0.minX >= 0 && $0.maxX <= width })
            XCTAssertGreaterThan(frames.last!.minY, 0)
            for (previous, next) in zip(frames, frames.dropFirst()) {
                XCTAssertTrue(next.minY >= previous.maxY || next.minX >= previous.maxX)
            }
        }
    }

    func testExactFitDoesNotWrapAndNextKeyStartsNewLine() {
        let frames = ShortcutFlowLayout.frames(for: [
            CGSize(width: 40, height: 30), CGSize(width: 54, height: 20), CGSize(width: 20, height: 20)
        ], width: 100)
        XCTAssertEqual(frames[1].maxX, 100)
        XCTAssertEqual(frames[1].minY, 0)
        XCTAssertEqual(frames[2].minX, 0)
        XCTAssertEqual(frames[2].minY, 36)
    }

    func testOversizedKeyIsConstrainedAndEmptyChordHasNoFrames() {
        let frames = ShortcutFlowLayout.frames(for: [CGSize(width: 500, height: 25)], width: 220)
        XCTAssertEqual(frames[0].width, 220)
        XCTAssertTrue(ShortcutFlowLayout.frames(for: [], width: 220).isEmpty)
    }
}
