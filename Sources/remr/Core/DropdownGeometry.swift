import Foundation
import CoreGraphics

/// Positions a floating dropdown below its trigger, flipping above when needed.
enum DropdownGeometry {
    static func frame(anchor: CGRect, size: CGSize, screen: CGRect,
                      preferAbove: Bool = false) -> CGRect {
        let inset: CGFloat = 8
        let gap: CGFloat = 6
        let available = screen.insetBy(dx: inset, dy: inset)
        let size = CGSize(width: min(size.width, available.width),
                          height: min(size.height, available.height))
        let below = anchor.minY - gap - size.height
        let above = anchor.maxY + gap
        let fitsBelow = below >= available.minY
        let fitsAbove = above + size.height <= available.maxY
        let y = preferAbove ? (fitsAbove ? above : below) : (fitsBelow ? below : above)
        return CGRect(x: min(max(anchor.maxX - size.width, available.minX), available.maxX - size.width),
                      y: min(max(y, available.minY), available.maxY - size.height),
                      width: size.width, height: size.height)
    }
}
