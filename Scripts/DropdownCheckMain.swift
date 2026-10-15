import Foundation
import CoreGraphics

@main
struct DropdownCheckMain {
    static func main() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = CGSize(width: 272, height: 306)
        let top = CGRect(x: 1200, y: 860, width: 80, height: 30)
        let below = DropdownGeometry.frame(anchor: top, size: size, screen: screen)
        precondition(below.maxY == top.minY - 6, "Dropdown should sit below a menu-bar trigger")
        let bottom = CGRect(x: 400, y: 10, width: 80, height: 30)
        let flipped = DropdownGeometry.frame(anchor: bottom, size: size, screen: screen)
        precondition(flipped.minY == bottom.maxY + 6, "Dropdown should flip above near the bottom")
        let left = DropdownGeometry.frame(anchor: CGRect(x: 0, y: 600, width: 20, height: 20), size: size, screen: screen)
        precondition(left.minX == 8, "Left edge must remain onscreen")
        let right = DropdownGeometry.frame(anchor: CGRect(x: 1430, y: 600, width: 20, height: 20), size: size, screen: screen)
        precondition(right.maxX == 1432, "Right edge must remain onscreen")
        let secondary = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let secondaryFrame = DropdownGeometry.frame(anchor: CGRect(x: -1900, y: 830, width: 60, height: 30), size: size, screen: secondary)
        precondition(secondary.insetBy(dx: 8, dy: 8).contains(secondaryFrame), "Support displays with negative coordinates")
        let small = CGRect(x: 0, y: 0, width: 240, height: 200)
        let constrained = DropdownGeometry.frame(anchor: top, size: size, screen: small)
        precondition(small.insetBy(dx: 8, dy: 8).contains(constrained), "Oversized dropdowns must fit the visible screen")
        let preferred = DropdownGeometry.frame(anchor: CGRect(x: 400, y: 400, width: 80, height: 30), size: size, screen: screen, preferAbove: true)
        precondition(preferred.minY == 436, "Honor above-anchor presentation when space allows")
        print("Dropdown placement checks passed (7 cases)")
    }
}
