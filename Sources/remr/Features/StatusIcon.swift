import AppKit

/// Status bar icon: the standard SF Symbol checkmark, template-mode so the
/// menu bar colors it black (light bar) or white (dark bar).
enum StatusIcon {
    static func makeIcon() -> NSImage {
        let image = NSImage(systemSymbolName: "checkmark.circle.fill",
                            accessibilityDescription: "remr")
            ?? NSImage(systemSymbolName: "checkmark", accessibilityDescription: "remr")
            ?? NSImage()
        image.isTemplate = true
        return image
    }
}
