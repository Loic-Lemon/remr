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

    /// Glyph configuration for the menu bar icons. The default (regular)
    /// weight reads thin at menu-bar size; one step heavier keeps the outline
    /// legible without looking bold. Weight can only be set alongside a point
    /// size, and 13 pt is what `NSImage(systemSymbolName:)` resolves to by
    /// default — pinning the same size here keeps each glyph's bounding box
    /// (and so the popover anchor) unchanged while thickening the stroke.
    private static let glyphConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)

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
            icon = normalized(configured(base, color: nil), isTemplate: true)
        case .accent:
            icon = normalized(configured(base, color: accentColor), isTemplate: false)
        case .custom:
            icon = normalized(configured(base, color: NSColor(color)), isTemplate: false)
        }
        guard badge != .none && count > 0 else { return icon }
        return badged(icon, count: count, isTemplate: icon.isTemplate)
    }

    /// Applies the menu bar stroke weight — and, when tinting, the palette
    /// colour — as one merged symbol configuration. Merging with `applying(_:)`
    /// keeps the weight when a colour is added.
    private static func configured(_ base: NSImage, color: NSColor?) -> NSImage {
        var configuration = glyphConfiguration
        if let color {
            configuration = configuration.applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        }
        return base.withSymbolConfiguration(configuration) ?? base
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

    /// Rasterize `draw` onto the fixed-size canvas at 2× resolution and return
    /// the result backed by a concrete bitmap.
    ///
    /// `NSImage(size:flipped:drawingHandler:)` produces a lazily rendered image
    /// with no bitmap representation: the first context that draws it wins, and
    /// that render is cached at the context's scale. On a 1× (non-Retina)
    /// display the symbol gets rasterized at 18×18 pixels — coarse and aliased
    /// — and that low-res cache then shows pixelated on Retina too. Rendering
    /// at a fixed 2× gives Retina a native bitmap and lets AppKit anti-alias
    /// the downscale on 1× displays.
    private static func canvas(_ draw: (NSRect) -> Void) -> NSImage {
        let scale: CGFloat = 2
        let pixelWidth = Int(canvasSize.width * scale)
        let pixelHeight = Int(canvasSize.height * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: pixelWidth,
                                         pixelsHigh: pixelHeight,
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else {
            return NSImage(size: canvasSize)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: scale, y: scale)
        draw(NSRect(origin: .zero, size: canvasSize))
        NSGraphicsContext.restoreGraphicsState()

        rep.size = canvasSize
        let image = NSImage(size: canvasSize)
        image.addRepresentation(rep)
        return image
    }

    /// Draw the symbol centered onto the fixed-size canvas. Template images
    /// draw their glyph shape (tinted later by the button); colored images
    /// carry their baked color.
    private static func normalized(_ image: NSImage, isTemplate: Bool) -> NSImage {
        let result = canvas { rect in
            let size = image.size
            let fit = min(1.0, min(rect.width / size.width, rect.height / size.height))
            let w = size.width * fit
            let h = size.height * fit
            let target = NSRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
            image.draw(in: target)
        }
        result.isTemplate = isTemplate
        result.accessibilityDescription = image.accessibilityDescription
        return result
    }

    /// Overlay a count disc on the top-right corner of the canvas.
    ///
    /// The composite keeps the base's template state. For Automatic the disc
    /// stays a template: the system tints it with the menu bar foreground and
    /// punches the digits out to the menu bar background, so the badge adapts
    /// to light and dark menu bars. Accent and Custom styles bake red-on-white
    /// as drawn.
    private static func badged(_ base: NSImage, count: Int, isTemplate: Bool) -> NSImage {
        let result = canvas { rect in
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
        }
        result.isTemplate = isTemplate
        result.accessibilityDescription = base.accessibilityDescription
        return result
    }
}
