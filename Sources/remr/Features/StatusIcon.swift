import AppKit

/// Status bar icon: SF Symbol bell.badge (template-mode so the
/// menu bar colors it black in light mode, white in dark mode).
enum StatusIcon {
    static func makeIcon() -> NSImage {
        let image = NSImage(systemSymbolName: "bell.badge",
                            accessibilityDescription: "remr")
            ?? NSImage(systemSymbolName: "bell", accessibilityDescription: "remr")
            ?? NSImage()
        image.isTemplate = true
        return image
    }
}
