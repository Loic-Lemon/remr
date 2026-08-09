import AppKit
import SwiftUI

/// remr-local tag colors. Reminders.app keeps its own tag colors in private
/// per-app storage (inaccessible via EventKit, like tags themselves), so
/// colors live here: a fixed palette, auto-assigned deterministically by tag
/// name, overridable per tag via the chip's context menu.
@MainActor
final class TagStore: ObservableObject {
    static let shared = TagStore()

    /// Tag name (lowercased) → palette index override, persisted.
    @Published private(set) var overrides: [String: Int] = [:]
    private let defaults = UserDefaults.standard
    private let overrideKey = "remr.tagColorOverrides"

    private static let names = [
        "Red", "Orange", "Yellow", "Green", "Teal", "Blue", "Indigo", "Purple", "Pink", "Gray",
    ]
    static let palette: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen, .systemTeal,
        .systemBlue, .systemIndigo, .systemPurple, .systemPink, .systemGray,
    ]

    init() {
        overrides = defaults.dictionary(forKey: overrideKey) as? [String: Int] ?? [:]
    }

    /// Palette color for a tag: user override if set, else a stable hash so
    /// the same tag always renders the same color across sessions.
    func color(for tag: String) -> Color {
        Color(nsColor: Self.palette[paletteIndex(for: tag)])
    }

    func paletteIndex(for tag: String) -> Int {
        let key = tag.lowercased()
        if let idx = overrides[key] { return idx % Self.palette.count }
        return Self.stableHash(key) % Self.palette.count
    }

    func setColor(for tag: String, paletteIndex: Int) {
        overrides[tag.lowercased()] = paletteIndex % Self.palette.count
        defaults.set(overrides, forKey: overrideKey)
    }

    static func colorName(_ index: Int) -> String {
        names[index % names.count]
    }

    /// Black or white depending on the chip's fill, for readable label text.
    static func textColor(on nsColor: NSColor) -> Color {
        let c = nsColor.usingColorSpace(.sRGB) ?? nsColor
        let luminance = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
        return luminance > 0.6 ? .black : .white
    }

    /// FNV-1a-ish; stable across launches and processes.
    private static func stableHash(_ s: String) -> Int {
        s.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fff_ffff }
    }
}
