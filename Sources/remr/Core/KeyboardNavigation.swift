import EventKit

/// The two recovery tabs rendered below the list sections.
enum RecoveryTab: String, CaseIterable {
    case completed
    case deleted
}

/// One keyboard-navigable row in the popover list, mirroring MainView's render order.
enum NavigableRow: Equatable {
    case reminder(String)        // EKReminder.calendarItemIdentifier
    case deleted(UUID)           // DeletedReminder.id
    case tabHeader(RecoveryTab)
}

/// Observed by the key monitor; pure input to `KeyboardRouter.action`.
struct KeyboardContext {
    var textFieldFocused: Bool   // first responder is EnterSubmitTextView (title/notes)
    var searchFieldFocused: Bool // first responder is the search NSTextField
    var selectionIsHeader: Bool
    var hasSelection: Bool
    var searchHasText: Bool
    var selectionIsReminder: Bool
    var selectionIsCompleted: Bool
    var hasUndo: Bool
}

/// A key event translated into an action for the executor to run.
enum KeyAction: Equatable {
    case none                    // pass the event through (return nil from monitor)
    case moveSelection(Int)      // delta: -1, +1, -10, +10
    case scrollPage(Int)         // scroll only, selection unchanged
    case toggleHeader            // ←/→ on a selected tab header
    case clearSelection
    case focusSearch             // "/" or ⌘F
    case focusTitle              // Tab from list, Shift+Tab from search
    case focusNotes              // Shift+Tab from search with a visible notes field
    case enterListMode           // Tab from search, Shift+Tab from title
    case clearSearchOrClose      // Esc with search text → clear; else close
    case closePopover
    case activateRow             // Enter: complete / restore / toggle header
    case openRow                 // ⌘Enter: open in Reminders
    case deleteRow               // ⌫: delete / delete forever
    case editRow                 // Edit the selected reminder
    case snoozeRow               // Snooze the selected reminder
    case undo                    // Undo the most recent undoable mutation
}

enum KeyboardRouter {
    /// Translate a key event into an action. Pure; unit-tested.
    static func action(keyCode: UInt16,
                       heldKeyCodes: Set<UInt16>,
                       context: KeyboardContext,
                       bindings: [BindableAction: KeyCombo] = DefaultBindings.all) -> KeyAction {
        // Tab matrix first, hard-coded — Tab is not bindable, so custom bindings can't claim it.
        if keyCode == 48 {
            if heldKeyCodes.contains(ModifierKey.shift.keyCode) {
                // Shift+Tab from search walks backward; the visible notes field
                // comes before the title in the focus chain.
                return context.searchFieldFocused ? .focusNotes : .focusSearch
            }
            if context.textFieldFocused { return .none } // text view owns Tab (dropdown accept, else onFocusForward)
            return context.searchFieldFocused ? .enterListMode : .focusTitle
        }

        let noFieldFocused = !context.textFieldFocused && !context.searchFieldFocused

        // Chord match — exact held-key-set equality, completed by a plain key
        // (modifiers-first convention: a modifier keyDown that tops up the set
        // must not hijack e.g. ⌘C while a chord key is held).
        guard let entry = bindings.first(where: {
            !$0.value.isEmpty
                && $0.value.keySet == heldKeyCodes
                && ModifierKey.canonicalKeyCode(for: keyCode) == nil
        }) else { return .none }
        let action = entry.key
        let combo = entry.value

        switch action {
        case .focusSearch:
            // Modifier chords (⌘F) focus from anywhere; bare keys ("/") only
            // when no field is focused, so typing a slash isn't swallowed.
            return (combo.hasModifier || noFieldFocused) ? .focusSearch : .none

        case .moveDown:
            return noFieldFocused ? .moveSelection(1) : .none

        case .moveUp:
            return noFieldFocused ? .moveSelection(-1) : .none

        case .pageDown:
            return noFieldFocused ? .moveSelection(10) : .none

        case .pageUp:
            return noFieldFocused ? .moveSelection(-10) : .none

        case .scrollDown:
            return noFieldFocused ? .scrollPage(1) : .none

        case .scrollUp:
            return noFieldFocused ? .scrollPage(-1) : .none

        case .toggleHeader:
            return noFieldFocused ? .toggleHeader : .none

        case .activateRow:
            return (noFieldFocused && context.hasSelection) ? .activateRow : .none
        case .openRow:
            return (noFieldFocused && context.hasSelection) ? .openRow : .none
        case .deleteRow:
            return (noFieldFocused && context.hasSelection) ? .deleteRow : .none
        case .editRow:
            return (noFieldFocused && context.selectionIsReminder) ? .editRow : .none
        case .snoozeRow:
            return (noFieldFocused && context.selectionIsReminder && !context.selectionIsCompleted) ? .snoozeRow : .none
        case .undo:
            return (noFieldFocused && context.hasUndo) ? .undo : .none

        case .closePopover: // Escape — text field owns it, then selection, then search text, else close.
            if context.textFieldFocused { return .none }
            if context.hasSelection { return .clearSelection }
            if context.searchHasText && context.searchFieldFocused { return .clearSearchOrClose }
            return .closePopover

        case .togglePopover:
            return .none
        case .quickAdd:
            return .none
        case .openCalendar:
            return .none
        }
    }
}

enum ListNavigation {
    /// The flat navigable order, mirroring MainView's render order exactly.
    static func rows(sections: [(ReminderSection, [EKReminder])],
                     filtered: [EKReminder], isSearching: Bool,
                     completed: [EKReminder], showCompleted: Bool,
                     deleted: [DeletedReminder], showDeleted: Bool,
                     hidesTabs: Bool = false) -> [NavigableRow] {
        if isSearching {
            // Recovery tabs are hidden during search; completed matches (when
            // shown) follow the active matches. All of them — no 5-row cap —
            // because a search is explicitly looking for those reminders.
            var rows: [NavigableRow] = filtered.map { .reminder($0.calendarItemIdentifier) }
            if showCompleted {
                rows.append(contentsOf: completed.map { (r: EKReminder) in
                    .reminder(r.calendarItemIdentifier)
                })
            }
            return rows
        }

        var rows: [NavigableRow] = []
        for (_, reminders) in sections {
            rows.append(contentsOf: reminders.map { .reminder($0.calendarItemIdentifier) })
        }
        // A tag filter narrows the list without flattening its sections, but
        // the recovery tabs are hidden the same way search hides them.
        if !hidesTabs {
            if !completed.isEmpty {
                rows.append(.tabHeader(.completed))
                if showCompleted {
                    rows.append(contentsOf: completed.prefix(5).map { .reminder($0.calendarItemIdentifier) })
                }
            }
            if !deleted.isEmpty {
                rows.append(.tabHeader(.deleted))
                if showDeleted {
                    rows.append(contentsOf: deleted.prefix(5).map { .deleted($0.id) })
                }
            }
        }
        return rows
    }

    static func selectedIndex(_ selection: NavigableRow?, in rows: [NavigableRow]) -> Int? {
        guard let selection else { return nil }
        return rows.firstIndex(of: selection)
    }

    static func move(fromIndex: Int?, by delta: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let fromIndex else { return delta < 0 ? count - 1 : 0 }
        return min(max(fromIndex + delta, 0), count - 1)
    }

    /// When `selection` has vanished from `rows` (completed, deleted, synced
    /// away), return the row that takes its place: the row at the same index
    /// it occupied in `previous`, else the last remaining row, else nil. A
    /// selection that is still present is returned unchanged.
    static func replacement(for selection: NavigableRow,
                            in rows: [NavigableRow],
                            previous: [NavigableRow]) -> NavigableRow? {
        if rows.contains(selection) { return selection }
        guard let oldIndex = previous.firstIndex(of: selection) else { return nil }
        if oldIndex < rows.count { return rows[oldIndex] }
        return rows.last
    }
}
