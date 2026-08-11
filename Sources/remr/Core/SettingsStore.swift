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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        bindings = Self.load(defaults: defaults, bindingsKey: bindingsKey)
        appearance = AppearanceMode(rawValue: defaults.string(forKey: appearanceKey) ?? "") ?? .system
        errorMessage = nil
    }

    func setAppearance(_ appearance: AppearanceMode) {
        guard self.appearance != appearance else { return }
        self.appearance = appearance
        defaults.set(appearance.rawValue, forKey: appearanceKey)
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
