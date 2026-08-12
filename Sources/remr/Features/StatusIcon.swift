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
                      color: Color) -> NSImage {
        let base = NSImage(systemSymbolName: symbol.systemName,
                           accessibilityDescription: "remr")
            ?? NSImage(systemSymbolName: "bell", accessibilityDescription: "remr")
            ?? NSImage()
        switch style {
        case .automatic:
            return normalized(base, isTemplate: true)
        case .accent:
            return normalized(tinted(base, with: accentColor), isTemplate: false)
        case .custom:
            return normalized(tinted(base, with: NSColor(color)), isTemplate: false)
        }
    }

    /// Apply the current icon settings to a status button.
    static func apply(to button: NSStatusBarButton,
                      symbol: MenuBarIconSymbol,
                      style: MenuBarIconStyle,
                      color: Color) {
        button.image = image(symbol: symbol, style: style, color: color)
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
}
