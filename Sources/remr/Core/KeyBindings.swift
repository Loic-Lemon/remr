import AppKit
import Carbon.HIToolbox

// MARK: - ModifierKey

/// The four modifier keys. Canonical (left) key codes are used for chord
/// matching — right-side variants normalize onto these.
enum ModifierKey: String, Codable, CaseIterable, Hashable {
    case control
    case option
    case shift
    case command

    /// Canonical key code (left variant) used for matching and Carbon registration.
    var keyCode: UInt16 {
        switch self {
        case .control: return 59 // kVK_Control
        case .option:  return 58 // kVK_Option
        case .shift:   return 56 // kVK_Shift
        case .command: return 55 // kVK_Command
        }
    }

    var symbol: String {
        switch self {
        case .control: return "⌃"
        case .option:  return "⌥"
        case .shift:   return "⇧"
        case .command: return "⌘"
        }
    }

    /// Canonical key code for a raw modifier key code (54–62), or nil for
    /// plain keys. Right-hand variants map to the left-hand canonical code.
    static func canonicalKeyCode(for keyCode: UInt16) -> UInt16? {
        switch keyCode {
        case 54, 55: return command.keyCode   // right / left command
        case 56, 60: return shift.keyCode     // left / right shift
        case 58, 61: return option.keyCode    // left / right option
        case 59, 62: return control.keyCode   // left / right control
        default: return nil
        }
    }
}

// MARK: - KeyElement

/// One block of a binding: a modifier key or a plain key.
enum KeyElement: Codable, Equatable, Hashable {
    case modifier(ModifierKey)
    case key(UInt16)

    /// Canonical key code(s) this block contributes to the chord.
    var keyCodes: [UInt16] {
        switch self {
        case .modifier(let modifier): return [modifier.keyCode]
        case .key(let code):          return [code]
        }
    }

    /// Display: "⌘", "F", "↓", "Return", …
    var displayString: String {
        switch self {
        case .modifier(let modifier): return modifier.symbol
        case .key(let code):          return KeyCombo.keyName(code)
        }
    }

    /// True when this block is a plain (non-modifier) key.
    var isKey: Bool {
        if case .key = self { return true }
        return false
    }

    /// Element from a key event: a modifier block for modifier keys, else the
    /// plain key. Modifier presses arrive as flagsChanged, so a keyDown is a
    /// plain key; this never fails for real key events.
    init?(event: NSEvent) {
        if let canonical = ModifierKey.canonicalKeyCode(for: event.keyCode),
           let modifier = ModifierKey.allCases.first(where: { $0.keyCode == canonical }) {
            self = .modifier(modifier)
        } else {
            self = .key(event.keyCode)
        }
    }

}

// MARK: - KeyCombo

/// An ordered list of key blocks forming ONE chord: every block held
/// simultaneously (e.g. ⌥⌘R = [⌥, ⌘, R]). Empty = the binding is disabled.
/// Display order is the block order; matching is order-independent
/// (exact held-key set equality).
struct KeyCombo: Codable, Equatable, Hashable {
    var elements: [KeyElement]

    init(_ elements: [KeyElement]) {
        self.elements = elements
    }

    /// Converts a non-modifier key-down and its supported modifiers into one complete chord.
    static func recorded(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> KeyCombo? {
        guard ModifierKey.canonicalKeyCode(for: keyCode) == nil else { return nil }

        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        var elements: [KeyElement] = []
        if flags.contains(.control) { elements.append(.modifier(.control)) }
        if flags.contains(.option)  { elements.append(.modifier(.option)) }
        if flags.contains(.shift)   { elements.append(.modifier(.shift)) }
        if flags.contains(.command) { elements.append(.modifier(.command)) }
        elements.append(.key(keyCode))
        return KeyCombo(elements)
    }

    /// Legacy persisted shape (previous single-key model), for migration.
    init(legacy: LegacyKeyCombo) {
        var elements: [KeyElement] = []
        if legacy.control { elements.append(.modifier(.control)) }
        if legacy.option  { elements.append(.modifier(.option)) }
        if legacy.shift   { elements.append(.modifier(.shift)) }
        if legacy.command { elements.append(.modifier(.command)) }
        elements.append(.key(legacy.keyCode))
        self.elements = elements
    }

    var isEmpty: Bool { elements.isEmpty }

    /// All canonical key codes that must be held simultaneously (deduplicated).
    var keySet: Set<UInt16> { Set(elements.flatMap(\.keyCodes)) }

    var hasModifier: Bool {
        elements.contains { element in
            if case .modifier = element { return true }
            return false
        }
    }

    /// Blocks joined in order: "⌘F", "⌥⌘R", "⇧Space". Empty → "".
    var displayString: String { elements.map(\.displayString).joined() }

    /// The plain key block's code, if this combo is a valid global-hotkey shape
    /// (non-empty, exactly one plain key, any number of modifiers); else nil.
    var globalHotkeyKeyCode: UInt16? {
        guard !elements.isEmpty else { return nil }
        let keys = elements.compactMap { element -> UInt16? in
            if case .key(let code) = element { return code }
            return nil
        }
        guard keys.count == 1 else { return nil }
        return keys[0]
    }

    /// Carbon modifier bitmask for the modifier blocks, for `RegisterEventHotKey`.
    var carbonModifierFlags: UInt32 {
        var flags: UInt32 = 0
        for element in elements {
            if case .modifier(let modifier) = element {
                switch modifier {
                case .command: flags |= UInt32(cmdKey)
                case .option:  flags |= UInt32(optionKey)
                case .shift:   flags |= UInt32(shiftKey)
                case .control: flags |= UInt32(controlKey)
                }
            }
        }
        return flags
    }

    /// Chord conflict: same held-key set (both non-empty). Exact equality of
    /// key sets, so nested chords like ⌘F vs ⌘F+R never shadow each other.
    func conflicts(with other: KeyCombo) -> Bool {
        !isEmpty && !other.isEmpty && keySet == other.keySet
    }

    /// US-layout key names — matches the router's "US keyboard key codes" assumption.
    static func keyName(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 36: return "Return"
        case 48: return "Tab"
        case 51: return "Delete"
        case 53: return "Escape"
        case 49: return "Space"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 121: return "PageDown"
        case 116: return "PageUp"
        case 44: return "/"
        case UInt16(kVK_ANSI_A): return "A"
        case UInt16(kVK_ANSI_B): return "B"
        case UInt16(kVK_ANSI_C): return "C"
        case UInt16(kVK_ANSI_D): return "D"
        case UInt16(kVK_ANSI_E): return "E"
        case UInt16(kVK_ANSI_F): return "F"
        case UInt16(kVK_ANSI_G): return "G"
        case UInt16(kVK_ANSI_H): return "H"
        case UInt16(kVK_ANSI_I): return "I"
        case UInt16(kVK_ANSI_J): return "J"
        case UInt16(kVK_ANSI_K): return "K"
        case UInt16(kVK_ANSI_L): return "L"
        case UInt16(kVK_ANSI_M): return "M"
        case UInt16(kVK_ANSI_N): return "N"
        case UInt16(kVK_ANSI_O): return "O"
        case UInt16(kVK_ANSI_P): return "P"
        case UInt16(kVK_ANSI_Q): return "Q"
        case UInt16(kVK_ANSI_R): return "R"
        case UInt16(kVK_ANSI_S): return "S"
        case UInt16(kVK_ANSI_T): return "T"
        case UInt16(kVK_ANSI_U): return "U"
        case UInt16(kVK_ANSI_V): return "V"
        case UInt16(kVK_ANSI_W): return "W"
        case UInt16(kVK_ANSI_X): return "X"
        case UInt16(kVK_ANSI_Y): return "Y"
        case UInt16(kVK_ANSI_Z): return "Z"
        case UInt16(kVK_ANSI_1): return "1"
        case UInt16(kVK_ANSI_2): return "2"
        case UInt16(kVK_ANSI_3): return "3"
        case UInt16(kVK_ANSI_4): return "4"
        case UInt16(kVK_ANSI_5): return "5"
        case UInt16(kVK_ANSI_6): return "6"
        case UInt16(kVK_ANSI_7): return "7"
        case UInt16(kVK_ANSI_8): return "8"
        case UInt16(kVK_ANSI_9): return "9"
        case UInt16(kVK_ANSI_0): return "0"
        default: return "Key \(keyCode)"
        }
    }
}

/// The previous single-key persisted shape. Loaded for migration when the new
/// `KeyCombo` JSON fails to decode; converted via `KeyCombo(legacy:)`.
struct LegacyKeyCombo: Codable {
    var keyCode: UInt16
    var command: Bool
    var shift: Bool
    var option: Bool
    var control: Bool
}

// MARK: - BindableAction

/// A configurable action. rawValue is the stable persistence key; allCases order
/// is the Settings row order (global hotkey first, then list actions).
enum BindableAction: String, CaseIterable, Identifiable {
    case togglePopover   // "Open remr from anywhere" — global Carbon hotkey
    case focusSearch     // "Focus search"
    case moveDown        // "Move selection down"
    case moveUp          // "Move selection up"
    case pageDown        // "Move down a page"
    case pageUp          // "Move up a page"
    case scrollDown      // "Scroll down"
    case scrollUp        // "Scroll up"
    case toggleHeader    // "Toggle recovery tab"
    case activateRow     // "Complete / restore row"
    case openRow         // "Open in Reminders"
    case deleteRow       // "Delete row"
    case closePopover    // "Close popover"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .togglePopover: return "Open remr from anywhere"
        case .focusSearch: return "Focus search"
        case .moveDown: return "Move selection down"
        case .moveUp: return "Move selection up"
        case .pageDown: return "Move down a page"
        case .pageUp: return "Move up a page"
        case .scrollDown: return "Scroll down"
        case .scrollUp: return "Scroll up"
        case .toggleHeader: return "Toggle recovery tab"
        case .activateRow: return "Complete / restore row"
        case .openRow: return "Open in Reminders"
        case .deleteRow: return "Delete row"
        case .closePopover: return "Close popover"
        }
    }
}

// MARK: - DefaultBindings

enum DefaultBindings {
    /// Source of truth for the router's default argument and for SettingsStore merging.
    /// One chord per action; search defaults to ⌘F.
    static let all: [BindableAction: KeyCombo] = [
        .togglePopover: KeyCombo([.modifier(.option), .modifier(.command), .key(15)]), // ⌥⌘R (kVK_ANSI_R)
        .focusSearch:   KeyCombo([.modifier(.command), .key(3)]),                      // ⌘F (was "/")
        .moveDown:      KeyCombo([.key(125)]),                                         // ↓
        .moveUp:        KeyCombo([.key(126)]),                                         // ↑
        .pageDown:      KeyCombo([.key(121)]),                                         // PageDown
        .pageUp:        KeyCombo([.key(116)]),                                         // PageUp
        .scrollDown:    KeyCombo([.key(49)]),                                          // Space
        .scrollUp:      KeyCombo([.modifier(.shift), .key(49)]),                       // ⇧Space
        .toggleHeader:  KeyCombo([.key(123)]),                                         // ←
        .activateRow:   KeyCombo([.key(36)]),                                          // Return
        .openRow:       KeyCombo([.modifier(.command), .key(36)]),                     // ⌘Return
        .deleteRow:     KeyCombo([.key(51)]),                                          // ⌫
        .closePopover:  KeyCombo([.key(53)]),                                          // Esc
    ]
}
