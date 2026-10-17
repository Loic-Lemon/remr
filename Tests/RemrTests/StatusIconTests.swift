import AppKit
import XCTest
@testable import remr

final class StatusIconTests: XCTestCase {
    private func bitmap(style: MenuBarIconStyle, count: Int) throws -> NSBitmapImageRep {
        let image = StatusIcon.image(symbol: .bell, style: style, color: .blue,
                                     badge: .overdue, count: count)
        XCTAssertEqual(image.size, StatusIcon.canvasSize)
        XCTAssertEqual(image.isTemplate, style == .automatic)
        return try XCTUnwrap(image.representations.first as? NSBitmapImageRep)
    }

    func testAutomaticBadgeDigitsChangeTemplateAlpha() throws {
        // Different numbers must change the alpha mask that macOS tints.
        // Opaque white text on an opaque disc produces identical masks.
        let one = try bitmap(style: .automatic, count: 1)
        for count in [3, 8, 10] {
            let other = try bitmap(style: .automatic, count: count)
            var changedPixels = 0
            for y in 0..<one.pixelsHigh {
                for x in 0..<one.pixelsWide {
                    let first = try XCTUnwrap(one.colorAt(x: x, y: y)).alphaComponent
                    let second = try XCTUnwrap(other.colorAt(x: x, y: y)).alphaComponent
                    if abs(first - second) > 0.1 { changedPixels += 1 }
                }
            }
            XCTAssertGreaterThan(changedPixels, 5, "Count \(count) needs visible cutout digits")
        }
    }

    func testColoredBadgesKeepOpaqueWhiteDigits() throws {
        for style in [MenuBarIconStyle.accent, .custom] {
            let rep = try bitmap(style: style, count: 3)
            var whitePixels = 0
            var redPixels = 0
            for y in 0..<rep.pixelsHigh {
                for x in 0..<rep.pixelsWide {
                    let color = try XCTUnwrap(rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                    guard color.alphaComponent > 0.9 else { continue }
                    if min(color.redComponent, color.greenComponent, color.blueComponent) > 0.9 {
                        whitePixels += 1
                    }
                    if color.redComponent > 0.6 && color.greenComponent < 0.5 {
                        redPixels += 1
                    }
                }
            }
            XCTAssertGreaterThan(whitePixels, 5)
            XCTAssertGreaterThan(redPixels, 20)
        }
    }
}
