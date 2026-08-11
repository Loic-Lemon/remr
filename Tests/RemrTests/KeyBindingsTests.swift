import XCTest
import AppKit
@testable import remr

@MainActor
final class KeyBindingsTests: XCTestCase {

    /// A fresh, unique UserDefaults suite per test, so no test can pollute another.
    private func makeStore() -> (SettingsStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "remr.test.\(UUID().uuidString)")!
        return (SettingsStore(defaults: defaults), defaults)
    }

    func testDefaultsCoverEveryAction() {
        XCTAssertEqual(Set(DefaultBindings.all.keys), Set(BindableAction.allCases))
        for combo in DefaultBindings.all.values {
            XCTAssertFalse(combo.isEmpty)
        }
    }

    func testEditSnoozeUndoDefaultsAndLabels() {
        XCTAssertEqual(BindableAction.editRow.label, "Edit selected reminder")
        XCTAssertEqual(BindableAction.snoozeRow.label, "Snooze selected reminder")
        XCTAssertEqual(BindableAction.undo.label, "Undo last action")
        XCTAssertEqual(DefaultBindings.all[.editRow], KeyCombo([.key(14)])) // kVK_ANSI_E
        XCTAssertEqual(DefaultBindings.all[.snoozeRow], KeyCombo([.key(1)])) // kVK_ANSI_S
        XCTAssertEqual(DefaultBindings.all[.undo], KeyCombo([.modifier(.command), .key(6)])) // kVK_ANSI_Z
    }

    func testQuickAddDefaultAndLabel() {
        let combo = KeyCombo([.modifier(.option), .modifier(.command), .key(45)]) // kVK_ANSI_N
        XCTAssertEqual(DefaultBindings.all[.quickAdd], combo)
        XCTAssertEqual(combo.displayString, "⌥⌘N")
        XCTAssertEqual(BindableAction.quickAdd.label, "Quick add reminder")
        XCTAssertTrue(BindableAction.quickAdd.isGlobalHotkey)
        XCTAssertEqual(combo.globalHotkeyKeyCode, 45)

        let (store, _) = makeStore()
        XCTAssertEqual(store.combo(for: .quickAdd), combo)
    }

    func testKeyComboCodableRoundTrip() {
        let combo = KeyCombo([.modifier(.command), .key(3)])
        let data = try! JSONEncoder().encode(combo)
        let decoded = try! JSONDecoder().decode(KeyCombo.self, from: data)
        XCTAssertEqual(decoded, combo)
    }

    func testDisplayString() {
        XCTAssertEqual(KeyCombo([.modifier(.option), .modifier(.command), .key(15)]).displayString, "⌥⌘R")
        XCTAssertEqual(KeyCombo([.modifier(.shift), .key(49)]).displayString, "⇧Space")
        XCTAssertEqual(KeyCombo([.modifier(.command), .key(3)]).displayString, "⌘F")
        XCTAssertEqual(KeyCombo([.key(125)]).displayString, "↓")
        XCTAssertEqual(KeyCombo([]).displayString, "")
    }

    func testRecordedChordIncludesSupportedModifiers() {
        let combo = KeyCombo.recorded(keyCode: 5, modifierFlags: [.option, .command])

        XCTAssertEqual(combo?.elements, [.modifier(.option), .modifier(.command), .key(5)])
        XCTAssertEqual(combo?.displayString, "⌥⌘G")
    }

    func testRecordedPlainKeyProducesOneKeyElement() {
        let combo = KeyCombo.recorded(keyCode: 5, modifierFlags: [])

        XCTAssertEqual(combo?.elements, [.key(5)])
    }

    func testRecordedModifierKeyIsIgnored() {
        XCTAssertNil(KeyCombo.recorded(keyCode: 55, modifierFlags: [.command]))
    }

    func testCanonicalModifierKeyCodes() {
        XCTAssertEqual(ModifierKey.canonicalKeyCode(for: 55), 55)  // left command
        XCTAssertEqual(ModifierKey.canonicalKeyCode(for: 54), 55)  // right command
        XCTAssertEqual(ModifierKey.canonicalKeyCode(for: 56), 56)  // left shift
        XCTAssertEqual(ModifierKey.canonicalKeyCode(for: 60), 56)  // right shift
        XCTAssertEqual(ModifierKey.canonicalKeyCode(for: 58), 58)  // left option
        XCTAssertEqual(ModifierKey.canonicalKeyCode(for: 61), 58)  // right option
        XCTAssertEqual(ModifierKey.canonicalKeyCode(for: 59), 59)  // left control
        XCTAssertEqual(ModifierKey.canonicalKeyCode(for: 62), 59)  // right control
        XCTAssertNil(ModifierKey.canonicalKeyCode(for: 3))         // plain key
    }

    func testKeySet() {
        XCTAssertEqual(KeyCombo([.modifier(.command), .key(3)]).keySet, [55, 3])
        // Matching is order-independent: the same chord built in reverse order.
        XCTAssertEqual(KeyCombo([.key(3), .modifier(.command)]).keySet, [55, 3])
    }

    func testGlobalHotkeyShape() {
        XCTAssertEqual(KeyCombo([.modifier(.option), .modifier(.command), .key(15)]).globalHotkeyKeyCode, 15)
        XCTAssertEqual(KeyCombo([.modifier(.command), .key(3)]).globalHotkeyKeyCode, 3)
        // Two plain keys is not a valid global-hotkey shape.
        XCTAssertNil(KeyCombo([.modifier(.command), .key(3), .key(15)]).globalHotkeyKeyCode)
        // Empty chord = disabled, no hotkey.
        XCTAssertNil(KeyCombo([]).globalHotkeyKeyCode)
    }

    func testConflicts() {
        XCTAssertTrue(KeyCombo([.modifier(.command), .key(3)]).conflicts(with: KeyCombo([.key(3), .modifier(.command)])))
        XCTAssertFalse(KeyCombo([.modifier(.command), .key(3)]).conflicts(with: KeyCombo([.modifier(.command), .key(3), .key(15)])))
        XCTAssertFalse(KeyCombo([]).conflicts(with: KeyCombo([.key(3)])))
    }

    func testLegacyMigration() {
        // Direct conversion: modifiers in order control → option → shift → command.
        let legacy = LegacyKeyCombo(keyCode: 15, command: true, shift: false, option: true, control: false)
        XCTAssertEqual(KeyCombo(legacy: legacy).elements, [.modifier(.option), .modifier(.command), .key(15)])

        // Load path: persisted legacy JSON (new-shape decode fails, legacy shape wins).
        let defaults = UserDefaults(suiteName: "remr.test.\(UUID().uuidString)")!
        defaults.set(
            Data(#"{"focusSearch":{"keyCode":3,"command":true,"shift":false,"option":false,"control":false}}"#.utf8),
            forKey: "remr.keyBindings"
        )
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.combo(for: .focusSearch), KeyCombo([.modifier(.command), .key(3)]))
    }

    func testAssignRejectsDuplicate() {
        let (store, _) = makeStore()
        let duplicate = KeyCombo([.modifier(.option), .modifier(.command), .key(15)])  // default togglePopover
        let result = store.assign(duplicate, to: .focusSearch)
        XCTAssertFalse(result)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(store.errorMessage!.contains("Already assigned"))
        XCTAssertEqual(store.combo(for: .focusSearch), DefaultBindings.all[.focusSearch])
    }

    func testAssignRejectsModifierOnlyComboWithoutMutation() {
        let (store, defaults) = makeStore()
        let original = store.combo(for: .focusSearch)

        XCTAssertFalse(store.assign(KeyCombo([.modifier(.command)]), to: .focusSearch))
        XCTAssertEqual(store.errorMessage, "The shortcut needs at least one non-modifier key")
        XCTAssertEqual(store.combo(for: .focusSearch), original)
        XCTAssertNil(defaults.data(forKey: "remr.keyBindings"))
    }

    func testAssignRejectsTabWithoutMutation() {
        let (store, defaults) = makeStore()
        let original = store.combo(for: .moveDown)

        XCTAssertFalse(store.assign(KeyCombo([.key(48)]), to: .moveDown))
        XCTAssertEqual(store.errorMessage, "Tab is reserved for focus navigation")
        XCTAssertEqual(store.combo(for: .moveDown), original)
        XCTAssertNil(defaults.data(forKey: "remr.keyBindings"))
    }

    func testInvalidPersistedModifierOnlyAndTabEntriesFallBackToDefaults() {
        let (_, defaults) = makeStore()
        let saved: [String: KeyCombo] = [
            BindableAction.focusSearch.rawValue: KeyCombo([.modifier(.command)]),
            BindableAction.moveDown.rawValue: KeyCombo([.key(48)])
        ]
        defaults.set(try! JSONEncoder().encode(saved), forKey: "remr.keyBindings")

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.combo(for: .focusSearch), DefaultBindings.all[.focusSearch])
        XCTAssertEqual(reloaded.combo(for: .moveDown), DefaultBindings.all[.moveDown])
    }

    func testRejectedAssignmentCanBeRetriedSuccessfully() {
        let (store, _) = makeStore()

        XCTAssertFalse(store.assign(KeyCombo([.modifier(.command)]), to: .focusSearch))
        XCTAssertEqual(store.errorMessage, "The shortcut needs at least one non-modifier key")
        XCTAssertTrue(store.assign(KeyCombo([.key(38)]), to: .focusSearch))
        XCTAssertEqual(store.combo(for: .focusSearch), KeyCombo([.key(38)]))
        XCTAssertNil(store.errorMessage)
    }

    func testSuccessfulNoOpClearsPreviousError() {
        let (store, _) = makeStore()
        let original = store.combo(for: .focusSearch)

        XCTAssertFalse(store.assign(KeyCombo([.modifier(.command)]), to: .focusSearch))
        XCTAssertEqual(store.errorMessage, "The shortcut needs at least one non-modifier key")
        XCTAssertTrue(store.assign(original, to: .focusSearch))
        XCTAssertNil(store.errorMessage)
    }

    func testAssignRejectsMultiKeyGlobal() {
        let (store, _) = makeStore()

        let multiKey = store.assign(KeyCombo([.modifier(.command), .key(3), .key(15)]), to: .togglePopover)
        XCTAssertFalse(multiKey)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(store.errorMessage!.contains("exactly one key"))

        // A single plain key is a valid (if aggressive) global hotkey.
        let plainKey = store.assign(KeyCombo([.key(3)]), to: .togglePopover)
        XCTAssertTrue(plainKey)
        XCTAssertEqual(store.combo(for: .togglePopover), KeyCombo([.key(3)]))

        // Empty chord disables the hotkey.
        let disabled = store.assign(KeyCombo([]), to: .togglePopover)
        XCTAssertTrue(disabled)
        XCTAssertEqual(store.combo(for: .togglePopover), KeyCombo([]))
    }

    func testQuickAddAcceptsValidReassignment() {
        let (store, defaults) = makeStore()
        let replacement = KeyCombo([.modifier(.command), .key(45)]) // ⌘N
        XCTAssertEqual(replacement.globalHotkeyKeyCode, 45)

        XCTAssertTrue(store.assign(replacement, to: .quickAdd))
        XCTAssertEqual(store.combo(for: .quickAdd), replacement)
        XCTAssertNil(store.errorMessage)

        // Persisted: a reloaded store keeps the override.
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.combo(for: .quickAdd), replacement)
    }

    func testQuickAddAcceptsEmptyDisable() {
        let (store, defaults) = makeStore()

        XCTAssertTrue(store.assign(KeyCombo([]), to: .quickAdd))
        XCTAssertTrue(store.combo(for: .quickAdd).isEmpty)
        XCTAssertNil(store.errorMessage)

        // Persisted: reload keeps the binding disabled.
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertTrue(reloaded.combo(for: .quickAdd).isEmpty)
    }

    func testQuickAddRejectsMultiPlainKeyCombo() {
        let (store, defaults) = makeStore()
        let original = store.combo(for: .quickAdd)

        // Two plain keys, no modifiers: not a valid global-hotkey shape.
        let multiPlain = KeyCombo([.key(3), .key(15)]) // F + R
        XCTAssertFalse(store.assign(multiPlain, to: .quickAdd))
        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(store.errorMessage!.contains("exactly one key"))
        XCTAssertEqual(store.combo(for: .quickAdd), original)
        XCTAssertNil(defaults.data(forKey: "remr.keyBindings"))
    }

    func testPersistAndReload() {
        let (store, defaults) = makeStore()
        XCTAssertTrue(store.assign(KeyCombo([.key(38)]), to: .moveDown))  // "J"
        XCTAssertTrue(store.assign(KeyCombo([.key(14)]), to: .editRow))   // "E"

        let second = SettingsStore(defaults: defaults)
        XCTAssertEqual(second.combo(for: .moveDown), KeyCombo([.key(38)]))
        XCTAssertEqual(second.combo(for: .editRow), KeyCombo([.key(14)]))
        XCTAssertEqual(second.combo(for: .focusSearch), DefaultBindings.all[.focusSearch])
        XCTAssertEqual(second.combo(for: .snoozeRow), DefaultBindings.all[.snoozeRow])
        XCTAssertEqual(second.combo(for: .undo), DefaultBindings.all[.undo])
    }

    func testResetToDefaults() {
        let (store, _) = makeStore()
        XCTAssertTrue(store.assign(KeyCombo([.key(38)]), to: .moveDown))
        store.resetToDefaults()
        XCTAssertEqual(store.bindings, DefaultBindings.all)
    }

    func testCorruptStoredDataFallsBackToDefaults() {
        let defaults = UserDefaults(suiteName: "remr.test.\(UUID().uuidString)")!
        defaults.set(Data("garbage".utf8), forKey: "remr.keyBindings")
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.bindings, DefaultBindings.all)
    }
}
