import AppKit
import Combine
import Foundation
import SwiftUI

/// User-selectable appearance modes for the app's SwiftUI surfaces.
/// The system option leaves the platform appearance unchanged.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    var id: Self { self }

    var label: String {
        switch self {
        case .system: return "Follow System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}
/// Keeps SwiftUI semantic colors and AppKit window appearance on the same
/// appearance value. Without this, explicit Light/Dark modes only reached
/// some roots while Follow System relied on the hosting window's inherited
/// color scheme, making opacity-based fills and hairlines resolve differently.
private struct RemrAppearanceModifier: ViewModifier {
    @ObservedObject private var settings: SettingsStore
    @Environment(\.colorScheme) private var inheritedColorScheme

    init(settings: SettingsStore) {
        _settings = ObservedObject(wrappedValue: settings)
    }

    func body(content: Content) -> some View {
        content
            .environment(\.colorScheme, settings.appearance.colorScheme ?? inheritedColorScheme)
    }
}

extension View {
    /// Resolves semantic SwiftUI colors from the same user-selected appearance
    /// that AppKit applies to the hosting window.
    func remrAppearance(using settings: SettingsStore) -> some View {
        modifier(RemrAppearanceModifier(settings: settings))
    }
}

 

/// Menu bar icon style: automatic (system black/white), accent (the macOS
/// accent colour), or custom (any user-picked colour).
enum MenuBarIconStyle: String, CaseIterable, Identifiable {
    case automatic
    case accent
    case custom

    var id: Self { self }

    var label: String {
        switch self {
        case .automatic: return "Automatic"
        case .accent: return "Accent colour"
        case .custom: return "Custom colour"
        }
    }

    /// Load from a persisted raw value, mapping the pre-rename names
    /// ("template"/"monochrome") to their current equivalents.
    static func load(rawValue: String?) -> MenuBarIconStyle {
        if let style = MenuBarIconStyle(rawValue: rawValue ?? "") { return style }
        switch rawValue {
        case "template": return .automatic
        case "monochrome": return .accent
        default: return .accent
        }
    }
}

/// Optional count shown on the menu bar icon.
enum MenuBarIconBadge: String, CaseIterable, Identifiable {
    case none
    case overdue
    case dueToday

    var id: Self { self }

    var label: String {
        switch self {
        case .none: return "None"
        case .overdue: return "Overdue"
        case .dueToday: return "Due today"
        }
    }
}

/// Predefined menu bar icons (SF Symbols).
enum MenuBarIconSymbol: String, CaseIterable, Identifiable {
    case bellBadge = "bell.badge"
    case bell = "bell"
    case checkmarkCircle = "checkmark.circle"
    case exclamationmarkCircle = "exclamationmark.circle"
    case clockBadge = "clock.badge"
    case tag = "tag"
    case flag = "flag"
    case star = "star"
    case moon = "moon"
    case sunMax = "sun.max"

    var id: Self { self }

    var label: String {
        switch self {
        case .bellBadge: return "Bell with badge"
        case .bell: return "Bell"
        case .checkmarkCircle: return "Checkmark circle"
        case .exclamationmarkCircle: return "Exclamation circle"
        case .clockBadge: return "Clock with badge"
        case .tag: return "Tag"
        case .flag: return "Flag"
        case .star: return "Star"
        case .moon: return "Moon"
        case .sunMax: return "Sun"
        }
    }

    var systemName: String { rawValue }
}

/// Persisted, live-applied keyboard bindings. Defaults come from
/// `DefaultBindings.all`; user overrides are stored as JSON in UserDefaults
/// under `remr.keyBindings` and merged over the defaults on load, so a
/// partial or corrupt store can never crash the app. Data written by the
/// previous single-key model is migrated on load.
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published private(set) var bindings: [BindableAction: KeyCombo]
    /// The app appearance, applied immediately and persisted independently of
    /// keyboard binding drafts.
    @Published private(set) var appearance: AppearanceMode
    /// Menu bar icon symbol (SF Symbol name).
    @Published private(set) var menuBarIconSymbol: MenuBarIconSymbol
    /// Menu bar icon style.
    @Published private(set) var menuBarIconStyle: MenuBarIconStyle
    /// Custom menu bar icon color (used when style is .custom).
    @Published private(set) var menuBarIconColor: Color
    /// Menu bar icon badge (count shown on the icon).
    @Published private(set) var menuBarIconBadge: MenuBarIconBadge

    /// Shown under the Keyboard section; set by assign() or by AppDelegate on
    /// hotkey registration failure.
    @Published var errorMessage: String?
    /// True while the settings recorder is capturing a key block. MainView's
    /// monitor defers every event while this is set, so the recorder's own
    /// (later-registered) monitor sees keys first regardless of which window
    /// is key. SettingsView drives it: true at capture start, false on
    /// commit/cancel/popover close.
    @Published var isCapturing: Bool = false

    private let defaults: UserDefaults
    private let bindingsKey = "remr.keyBindings"
    private let appearanceKey = "remr.appearance"
    private let menuBarIconSymbolKey = "remr.menuBarIconSymbol"
    private let menuBarIconStyleKey = "remr.menuBarIconStyle"
    private let menuBarIconBadgeKey = "remr.menuBarIconBadge"
    /// Canonical sRGB components [r, g, b, a] — the single persisted form so a
    /// reloaded color is always the exact representation the picker set.
    private let menuBarIconColorRGBAKey = "remr.menuBarIconColorRGBA"
    /// Legacy persisted form (archived NSColor) from before canonicalization.
    private let menuBarIconColorKey = "remr.menuBarIconColor"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        bindings = Self.load(defaults: defaults, bindingsKey: bindingsKey)
        appearance = AppearanceMode(rawValue: defaults.string(forKey: appearanceKey) ?? "") ?? .system
        menuBarIconSymbol = MenuBarIconSymbol(rawValue: defaults.string(forKey: menuBarIconSymbolKey) ?? "") ?? .bellBadge
        menuBarIconStyle = MenuBarIconStyle.load(rawValue: defaults.string(forKey: menuBarIconStyleKey))
        menuBarIconBadge = MenuBarIconBadge(rawValue: defaults.string(forKey: menuBarIconBadgeKey) ?? "") ?? .none
        menuBarIconColor = Self.loadColor(defaults: defaults,
                                          rgbaKey: menuBarIconColorRGBAKey,
                                          legacyKey: menuBarIconColorKey) ?? .accentColor
        errorMessage = nil
    }

    func setAppearance(_ appearance: AppearanceMode) {
        guard self.appearance != appearance else { return }
        self.appearance = appearance
        defaults.set(appearance.rawValue, forKey: appearanceKey)
    }

    func setMenuBarIconSymbol(_ symbol: MenuBarIconSymbol) {
        guard menuBarIconSymbol != symbol else { return }
        menuBarIconSymbol = symbol
    }

    func setMenuBarIconStyle(_ style: MenuBarIconStyle) {
        guard menuBarIconStyle != style else { return }
        menuBarIconStyle = style
        defaults.set(style.rawValue, forKey: menuBarIconStyleKey)
    }

    func setMenuBarIconBadge(_ badge: MenuBarIconBadge) {
        guard menuBarIconBadge != badge else { return }
        menuBarIconBadge = badge
        defaults.set(badge.rawValue, forKey: menuBarIconBadgeKey)
    }

    func setMenuBarIconColor(_ color: Color) {
        let rgba = Self.canonicalComponents(of: color)
        let canonical = Color(red: rgba[0], green: rgba[1], blue: rgba[2], opacity: rgba[3])
        guard menuBarIconColor != canonical else { return }
        menuBarIconColor = canonical
        defaults.set(rgba, forKey: menuBarIconColorRGBAKey)
    }

    /// Reduce a color to rounded sRGB components (6 decimal places). The
    /// SwiftUI↔AppKit bridge rounds through float32, so without rounding the
    /// persisted and reloaded doubles drift and `Color` equality (and the
    /// picker's sync) would depend on bridge internals.
    private static func canonicalComponents(of color: Color) -> [Double] {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        return [ns.redComponent, ns.greenComponent, ns.blueComponent, ns.alphaComponent]
            .map { Double(($0 * 1_000_000).rounded()) / 1_000_000 }
    }

    /// Load the menu bar icon color: canonical sRGB components first, then the
    /// legacy archived-NSColor form (migrated to the canonical form on load).
    private static func loadColor(defaults: UserDefaults,
                                  rgbaKey: String,
                                  legacyKey: String) -> Color? {
        if let rgba = defaults.array(forKey: rgbaKey) as? [Double], rgba.count == 4 {
            return Color(red: rgba[0], green: rgba[1], blue: rgba[2], opacity: rgba[3])
        }
        guard let data = defaults.data(forKey: legacyKey),
              let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data),
              let srgb = color.usingColorSpace(.sRGB) else { return nil }
        let nsColor = NSColor(srgbRed: srgb.redComponent, green: srgb.greenComponent,
                              blue: srgb.blueComponent, alpha: srgb.alphaComponent)
        let rgba = canonicalComponents(of: Color(nsColor))
        defaults.set(rgba, forKey: rgbaKey)
        return Color(red: rgba[0], green: rgba[1], blue: rgba[2], opacity: rgba[3])
    }

    private static func load(defaults: UserDefaults, bindingsKey: String) -> [BindableAction: KeyCombo] {
        guard let data = defaults.data(forKey: bindingsKey) else { return DefaultBindings.all }
        let saved: [(BindableAction, KeyCombo)]
        if let current = try? JSONDecoder().decode([String: KeyCombo].self, from: data) {
            saved = savedByAction(current)
        } else if let legacy = try? JSONDecoder().decode([String: LegacyKeyCombo].self, from: data) {
            // Migrate the previously-shipped single-key persisted format.
            saved = savedByAction(legacy.mapValues { KeyCombo(legacy: $0) })
        } else {
            return DefaultBindings.all  // corrupt data: fall back to defaults
        }
        // Unknown rawValues and invalid intrinsic shapes are dropped by savedByAction.
        var merged = DefaultBindings.all.merging(saved) { _, new in new }
        // Corrupt data can persist two actions with the same keySet; the router
        // matches bindings.first(where:) on a Dictionary, which would be
        // nondeterministic. Earlier actions (allCases order) win; a conflicted
        // action reverts to its default.
        var seen = Set<Set<UInt16>>()
        for action in BindableAction.allCases {
            var combo = merged[action] ?? DefaultBindings.all[action]!
            if !combo.isEmpty, seen.contains(combo.keySet) {
                combo = DefaultBindings.all[action]!
            }
            merged[action] = combo
            if !combo.isEmpty { seen.insert(combo.keySet) }
        }
        return merged
    }

    /// Intrinsic shape validation shared by loading and assignment. Empty
    /// combos are valid because they disable a binding.
    private static func validationError(for combo: KeyCombo, action: BindableAction) -> String? {
        guard !combo.isEmpty else { return nil }

        let hasPlainKey = combo.elements.contains { element in
            if case .key = element { return true }
            return false
        }
        guard hasPlainKey else { return "The shortcut needs at least one non-modifier key" }

        let containsTab = combo.elements.contains { element in
            if case .key(48) = element { return true }
            return false
        }
        guard !containsTab else { return "Tab is reserved for focus navigation" }

        if action.isGlobalHotkey && combo.globalHotkeyKeyCode == nil {
            return "The global shortcut needs exactly one key (e.g. ⌥⌘R)"
        }
        return nil
    }

    /// Map persisted rawValue keys to actions, dropping any unknown keys or
    /// entries with invalid intrinsic shapes.
    private static func savedByAction(_ saved: [String: KeyCombo]) -> [(BindableAction, KeyCombo)] {
        saved.compactMap { key, combo in
            guard let action = BindableAction(rawValue: key),
                  validationError(for: combo, action: action) == nil else {
                return nil
            }
            return (action, combo)
        }
    }

    func combo(for action: BindableAction) -> KeyCombo {
        bindings[action] ?? DefaultBindings.all[action]!
    }

    /// Assign a chord to an action. Returns false (with `errorMessage` set)
    /// when the chord conflicts with another action's binding (same held-key
    /// set) or — for the global hotkey — isn't exactly one plain key plus any
    /// modifiers. An empty chord is allowed: it disables the binding (and, for
    /// the global hotkey, registers nothing). Whole-dictionary replacement so
    /// `@Published` emits.
    @discardableResult
    func assign(_ combo: KeyCombo, to action: BindableAction) -> Bool {
        errorMessage = nil
        if combo == bindings[action] { return true }  // no-op

        if let error = Self.validationError(for: combo, action: action) {
            errorMessage = error
            return false
        }

        for (other, otherCombo) in bindings where other != action && combo.conflicts(with: otherCombo) {
            errorMessage = "Already assigned to \(other.label)"
            return false
        }

        var newBindings = bindings
        newBindings[action] = combo
        bindings = newBindings
        persist()
        return true
    }

    /// Validate a set of drafts against the current bindings (drafts override
    /// saved values). Returns per-action error strings; an empty dictionary
    /// means the whole set is valid. Shape errors come first, then conflict
    /// errors between any two actions (both are flagged).
    func validate(_ drafts: [BindableAction: KeyCombo]) -> [BindableAction: String] {
        var merged = bindings
        for (action, combo) in drafts { merged[action] = combo }

        var errors: [BindableAction: String] = [:]
        for (action, combo) in merged {
            if let error = Self.validationError(for: combo, action: action) {
                errors[action] = error
            }
        }
        let actions = Array(merged.keys)
        for i in 0..<actions.count {
            for j in (i + 1)..<actions.count {
                let a = actions[i], b = actions[j]
                let ca = merged[a]!, cb = merged[b]!
                if ca.conflicts(with: cb) {
                    errors[a] = "Already assigned to \(b.label)"
                    errors[b] = "Already assigned to \(a.label)"
                }
            }
        }
        return errors
    }

    /// Persist a set of drafts as one atomic change. Returns false (with
    /// `errorMessage` set to the first error) when any draft is invalid;
    /// nothing is persisted until the whole set validates.
    @discardableResult
    func commit(_ drafts: [BindableAction: KeyCombo]) -> Bool {
        let errors = validate(drafts)
        guard errors.isEmpty else {
            errorMessage = errors.values.first
            return false
        }
        var merged = bindings
        for (action, combo) in drafts { merged[action] = combo }
        bindings = merged
        errorMessage = nil
        persist()
        return true
    }

    func resetToDefaults() {
        bindings = DefaultBindings.all
        errorMessage = nil
        persist()
    }

    private func persist() {
        let keyedByRawValue = Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(keyedByRawValue) else { return }
        defaults.set(data, forKey: bindingsKey)
    }
}
