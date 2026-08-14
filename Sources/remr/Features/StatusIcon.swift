import AppKit
import SwiftUI

/// Renders the status bar icon from the user's settings. The automatic style
/// keeps the symbol a template image so the system colors it to match the
/// menu bar (black in light mode, white in dark mode). Accent and custom
/// styles bake a concrete color into the image with a palette symbol
/// configuration: `contentTintColor` does not tint status bar buttons, so
/// the color must be part of the image itself.
///
/// Every style is normalized onto a fixed-size canvas before it reaches the
/// status button. SF Symbols have different pixel bounding boxes (bell.badge
/// is 15x17, sun.max 16x16, moon 15x15), and the status button's frame — and
/// with it the position of the popover anchored to it — changes with the
/// image size. A constant-size image keeps the button's frame constant, so
/// switching icons never makes the popover jump.
enum StatusIcon {
    /// The size every icon is normalized to. Large enough for the widest
    /// symbol at the status bar's point size, with a little breathing room.
    static let canvasSize = NSSize(width: 18, height: 18)

    /// The current icon as an image. Shared by the status item and the live
    /// preview in Settings.
    static func image(symbol: MenuBarIconSymbol,
                      style: MenuBarIconStyle,
                      color: Color,
                      badge: MenuBarIconBadge = .none,
                      count: Int = 0) -> NSImage {
        let base = NSImage(systemSymbolName: symbol.systemName,
                           accessibilityDescription: "remr")
            ?? NSImage(systemSymbolName: "bell", accessibilityDescription: "remr")
            ?? NSImage()
        let icon: NSImage
        switch style {
        case .automatic:
            icon = normalized(base, isTemplate: true)
        case .accent:
            icon = normalized(tinted(base, with: accentColor), isTemplate: false)
        case .custom:
            icon = normalized(tinted(base, with: NSColor(color)), isTemplate: false)
        }
        guard badge != .none && count > 0 else { return icon }
        return badged(icon, count: count, isTemplate: icon.isTemplate)
    }

    /// Apply the current icon settings to a status button.
    static func apply(to button: NSStatusBarButton,
                      symbol: MenuBarIconSymbol,
                      style: MenuBarIconStyle,
                      color: Color,
                      badge: MenuBarIconBadge = .none,
                      count: Int = 0) {
        button.image = image(symbol: symbol, style: style, color: color,
                             badge: badge, count: count)
    }

    /// The macOS accent colour resolved against the current appearance and
    /// reduced to a concrete sRGB color. Resolving at bake time (instead of
    /// passing the dynamic `controlAccentColor` into the symbol
    /// configuration) keeps the rendered color deterministic.
    private static var accentColor: NSColor {
        var resolved = NSColor.controlAccentColor
        let appearance = NSApp?.effectiveAppearance ?? NSAppearance(named: .aqua)!
        appearance.performAsCurrentDrawingAppearance {
            resolved = NSColor.controlAccentColor.usingColorSpace(.sRGB)
                ?? NSColor.controlAccentColor
        }
        return resolved
    }

    /// Bake a single color into the symbol.
    private static func tinted(_ base: NSImage, with color: NSColor) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(paletteColors: [color])
        return base.withSymbolConfiguration(configuration) ?? base
    }

    /// Draw the symbol centered onto the fixed-size canvas. Template images
    /// draw their glyph shape (tinted later by the button); colored images
    /// carry their baked color.
    private static func normalized(_ image: NSImage, isTemplate: Bool) -> NSImage {
        let canvas = NSImage(size: canvasSize, flipped: false) { rect in
            let size = image.size
            let fit = min(1.0, min(rect.width / size.width, rect.height / size.height))
            let w = size.width * fit
            let h = size.height * fit
            let target = NSRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
            image.draw(in: target)
            return true
        }
        canvas.isTemplate = isTemplate
        canvas.accessibilityDescription = image.accessibilityDescription
        return canvas
    }

    /// Overlay a count disc on the top-right corner of the canvas.
    ///
    /// The composite keeps the base's template state. For Automatic the disc
    /// stays a template: the system tints it with the menu bar foreground and
    /// punches the digits out to the menu bar background, so the badge adapts
    /// to light and dark menu bars. Accent and Custom styles bake red-on-white
    /// as drawn.
    private static func badged(_ base: NSImage, count: Int, isTemplate: Bool) -> NSImage {
        let composite = NSImage(size: canvasSize, flipped: false) { rect in
            base.draw(in: rect)

            let center = NSPoint(x: rect.width - 6, y: rect.height - 6)
            let radius: CGFloat = 5.5
            let circleRect = NSRect(x: center.x - radius, y: center.y - radius,
                                    width: radius * 2, height: radius * 2)
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: circleRect).fill()

            let text: NSString = (count > 9 ? "9+" : "\(count)") as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 8, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let textSize = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: center.x - textSize.width / 2,
                                  y: center.y - textSize.height / 2),
                      withAttributes: attributes)
            return true
        }
        composite.isTemplate = isTemplate
        composite.accessibilityDescription = base.accessibilityDescription
        return composite
    }
}
