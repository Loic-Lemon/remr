import XCTest
import EventKit
@testable import remr

final class KeyboardNavigationTests: XCTestCase {

    // MARK: - Fixtures

    private func makeReminder(_ title: String) -> EKReminder {
        let reminder = EKReminder(eventStore: EKEventStore())
        reminder.title = title
        return reminder
    }

    private func makeDeleted(_ title: String) -> DeletedReminder {
        DeletedReminder(
            id: UUID(),
            title: title,
            notes: nil,
            dueDate: nil,
            isAllDay: false,
            priority: 0,
            calendarIdentifier: nil,
            location: nil,
            deletedAt: Date()
        )
    }

    private func section(_ kind: ReminderSection, _ reminders: [EKReminder]) -> (ReminderSection, [EKReminder]) {
        (kind, reminders)
    }

    private func context(
        textFieldFocused: Bool = false,
        searchFieldFocused: Bool = false,
        selectionIsHeader: Bool = false,
        hasSelection: Bool = false,
        searchHasText: Bool = false,
        selectionIsReminder: Bool = false,
        selectionIsCompleted: Bool = false,
        hasUndo: Bool = false
    ) -> KeyboardContext {
        KeyboardContext(
            textFieldFocused: textFieldFocused,
            searchFieldFocused: searchFieldFocused,
            selectionIsHeader: selectionIsHeader,
            hasSelection: hasSelection,
            searchHasText: searchHasText,
            selectionIsReminder: selectionIsReminder,
            selectionIsCompleted: selectionIsCompleted,
            hasUndo: hasUndo
        )
    }

    // MARK: - ListNavigation.rows

    /// (a) Non-search: section rows in overdue → today → later order with section
    /// headers absent, then `.tabHeader(.completed)` + rows when non-empty and
    /// expanded, then `.tabHeader(.deleted)` + rows.
    func testRowsNonSearchOrderAndHeaders() {
        let overdue = [makeReminder("o1"), makeReminder("o2")]
        let today = [makeReminder("t1")]
        let later = [makeReminder("l1"), makeReminder("l2"), makeReminder("l3")]
        let completed = [makeReminder("c1"), makeReminder("c2")]
        let deleted = [makeDeleted("d1"), makeDeleted("d2")]

        let rows = ListNavigation.rows(
            sections: [section(.overdue, overdue), section(.today, today), section(.future, later)],
            filtered: [],
            isSearching: false,
            completed: completed,
            showCompleted: true,
            deleted: deleted,
            showDeleted: true
        )

        // 2 + 1 + 3 section rows, then completed header + 2, deleted header + 2.
        XCTAssertEqual(rows.count, 12)
        XCTAssertEqual(
            rows,
            overdue.map { .reminder($0.calendarItemIdentifier) }
                + today.map { .reminder($0.calendarItemIdentifier) }
                + later.map { .reminder($0.calendarItemIdentifier) }
                + [.tabHeader(.completed)]
                + completed.map { .reminder($0.calendarItemIdentifier) }
                + [.tabHeader(.deleted)]
                + deleted.map { .deleted($0.id) }
        )
        // Explicit header positions (ids of unsaved reminders may be empty —
        // order, counts, and header positions are the load-bearing assertions).
        XCTAssertEqual(rows[6], .tabHeader(.completed))
        XCTAssertEqual(rows[9], .tabHeader(.deleted))
    }

    /// Ongoing rows stay pinned ahead of the chronological sections while recovery
    /// headers and rows remain at the end of the navigable list.
    func testRowsOngoingSectionPrecedesChronologicalAndRecoveryRows() {
        let ongoing = [makeReminder("ongoing1"), makeReminder("ongoing2")]
        let overdue = [makeReminder("overdue1")]
        let today = [makeReminder("today1"), makeReminder("today2")]
        let future = [makeReminder("future1")]
        let completed = [makeReminder("completed1")]
        let deleted = [makeDeleted("deleted1")]

        let rows = ListNavigation.rows(
            sections: [
                section(.ongoing, ongoing),
                section(.overdue, overdue),
                section(.today, today),
                section(.future, future)
            ],
            filtered: [],
            isSearching: false,
            completed: completed,
            showCompleted: true,
            deleted: deleted,
            showDeleted: true
        )

        XCTAssertEqual(
            rows,
            ongoing.map { .reminder($0.calendarItemIdentifier) }
                + overdue.map { .reminder($0.calendarItemIdentifier) }
                + today.map { .reminder($0.calendarItemIdentifier) }
                + future.map { .reminder($0.calendarItemIdentifier) }
                + [.tabHeader(.completed)]
                + completed.map { .reminder($0.calendarItemIdentifier) }
                + [.tabHeader(.deleted)]
                + deleted.map { .deleted($0.id) }
        )
    }

    /// (b) Collapsed tabs contribute only the header.
    func testRowsCollapsedTabsContributeOnlyHeader() {
        let overdue = [makeReminder("o1")]
        let completed = [makeReminder("c1"), makeReminder("c2")]
        let deleted = [makeDeleted("d1")]

        let rows = ListNavigation.rows(
            sections: [section(.overdue, overdue)],
            filtered: [],
            isSearching: false,
            completed: completed,
            showCompleted: false,
            deleted: deleted,
            showDeleted: false
        )

        XCTAssertEqual(
            rows,
            [.reminder(overdue[0].calendarItemIdentifier), .tabHeader(.completed), .tabHeader(.deleted)]
        )
    }

    /// (c) Empty completed/deleted lists contribute no rows at all.
    func testRowsEmptyRecoveryListsContributeNothing() {
        let overdue = [makeReminder("o1")]

        let rows = ListNavigation.rows(
            sections: [section(.overdue, overdue)],
            filtered: [],
            isSearching: false,
            completed: [],
            showCompleted: true,
            deleted: [],
            showDeleted: true
        )

        XCTAssertEqual(rows, [.reminder(overdue[0].calendarItemIdentifier)])

        // Nothing at all when every list is empty.
        let empty = ListNavigation.rows(
            sections: [],
            filtered: [],
            isSearching: false,
            completed: [],
            showCompleted: true,
            deleted: [],
            showDeleted: true
        )
        XCTAssertTrue(empty.isEmpty)
    }

    /// Search mode: active matches first, then every completed match (no cap,
    /// no tab headers, no deleted rows).
    func testRowsSearchModeAppendsCompletedMatches() {
        let overdue = [makeReminder("o1")]
        let completed = [makeReminder("c1"), makeReminder("c2")]
        let deleted = [makeDeleted("d1")]
        let filtered = [makeReminder("f1"), makeReminder("f2")]

        let rows = ListNavigation.rows(
            sections: [section(.overdue, overdue)],
            filtered: filtered,
            isSearching: true,
            completed: completed,
            showCompleted: true,
            deleted: deleted,
            showDeleted: true
        )

        let expected: [NavigableRow] = filtered.map { .reminder($0.calendarItemIdentifier) }
            + completed.map { .reminder($0.calendarItemIdentifier) }
        XCTAssertEqual(rows, expected)
        XCTAssertFalse(rows.contains { row in
            if case .tabHeader = row { return true }
            return false
        })
        XCTAssertFalse(rows.contains { row in
            if case .deleted = row { return true }
            return false
        })
    }

    /// Search mode without `showCompleted` returns only the active matches.
    func testRowsSearchModeHidesCompletedWhenNotShown() {
        let completed = [makeReminder("c1")]
        let filtered = [makeReminder("f1")]

        let rows = ListNavigation.rows(
            sections: [],
            filtered: filtered,
            isSearching: true,
            completed: completed,
            showCompleted: false,
            deleted: [],
            showDeleted: false
        )

        XCTAssertEqual(rows, [.reminder(filtered[0].calendarItemIdentifier)])
    }

    /// Search results are not capped at five the way the recovery tabs are.
    func testRowsSearchModeDoesNotCapCompleted() {
        let completed = (1...7).map { makeReminder("c\($0)") }

        let rows = ListNavigation.rows(
            sections: [],
            filtered: [],
            isSearching: true,
            completed: completed,
            showCompleted: true,
            deleted: [],
            showDeleted: false
        )

        XCTAssertEqual(rows.count, 7)
    }

    /// (e) Completed and deleted rows are capped at 5 each.
    func testRowsCapsRecoveryListsAtFive() {
        let completed = (1...7).map { makeReminder("c\($0)") }
        let deleted = (1...7).map { makeDeleted("d\($0)") }

        let rows = ListNavigation.rows(
            sections: [],
            filtered: [],
            isSearching: false,
            completed: completed,
            showCompleted: true,
            deleted: deleted,
            showDeleted: true
        )

        XCTAssertEqual(rows.count, 1 + 5 + 1 + 5)
        XCTAssertEqual(rows[0], .tabHeader(.completed))
        XCTAssertEqual(rows[6], .tabHeader(.deleted))
        XCTAssertEqual(
            Array(rows[1..<6]),
            completed.prefix(5).map { .reminder($0.calendarItemIdentifier) }
        )
        XCTAssertEqual(
            Array(rows[7..<12]),
            deleted.prefix(5).map { .deleted($0.id) }
        )
    }

    // MARK: - ListNavigation.move

    func testMoveNilIndexDownToFirst() {
        XCTAssertEqual(ListNavigation.move(fromIndex: nil, by: 1, count: 3), 0)
        XCTAssertEqual(ListNavigation.move(fromIndex: nil, by: 10, count: 3), 0)
    }

    func testMoveNilIndexUpToLast() {
        XCTAssertEqual(ListNavigation.move(fromIndex: nil, by: -1, count: 3), 2)
        XCTAssertEqual(ListNavigation.move(fromIndex: nil, by: -10, count: 3), 2)
    }

    func testMoveClampsAtBottomNoWrap() {
        XCTAssertEqual(ListNavigation.move(fromIndex: 0, by: -1, count: 3), 0)
        XCTAssertEqual(ListNavigation.move(fromIndex: 0, by: -10, count: 3), 0)
    }

    func testMoveClampsAtTopNoWrap() {
        XCTAssertEqual(ListNavigation.move(fromIndex: 2, by: 1, count: 3), 2)
        XCTAssertEqual(ListNavigation.move(fromIndex: 2, by: 10, count: 3), 2)
    }

    func testMovePageDeltasClamp() {
        XCTAssertEqual(ListNavigation.move(fromIndex: 1, by: 10, count: 3), 2)
        XCTAssertEqual(ListNavigation.move(fromIndex: 1, by: -10, count: 3), 0)
    }

    func testMoveNormalSteps() {
        XCTAssertEqual(ListNavigation.move(fromIndex: 1, by: 1, count: 3), 2)
        XCTAssertEqual(ListNavigation.move(fromIndex: 2, by: -1, count: 3), 1)
        XCTAssertEqual(ListNavigation.move(fromIndex: 1, by: -1, count: 3), 0)
    }

    func testMoveEmptyRows() {
        XCTAssertNil(ListNavigation.move(fromIndex: nil, by: 1, count: 0))
        XCTAssertNil(ListNavigation.move(fromIndex: 3, by: -1, count: 0))
    }

    // MARK: - ListNavigation.selectedIndex

    func testSelectedIndexAbsentOrNotInRows() {
        let rows: [NavigableRow] = [.reminder("a"), .tabHeader(.completed), .deleted(UUID())]
        XCTAssertNil(ListNavigation.selectedIndex(nil, in: rows))
        XCTAssertNil(ListNavigation.selectedIndex(.reminder("nope"), in: rows))
        XCTAssertNil(ListNavigation.selectedIndex(.tabHeader(.deleted), in: rows))
        XCTAssertNil(ListNavigation.selectedIndex(.reminder("a"), in: []))
    }

    func testSelectedIndexFound() {
        let deletedID = UUID()
        let rows: [NavigableRow] = [.reminder("a"), .tabHeader(.completed), .deleted(deletedID), .tabHeader(.deleted)]
        XCTAssertEqual(ListNavigation.selectedIndex(.reminder("a"), in: rows), 0)
        XCTAssertEqual(ListNavigation.selectedIndex(.tabHeader(.completed), in: rows), 1)
        XCTAssertEqual(ListNavigation.selectedIndex(.deleted(deletedID), in: rows), 2)
        XCTAssertEqual(ListNavigation.selectedIndex(.tabHeader(.deleted), in: rows), 3)
    }

    // MARK: - ListNavigation.replacement

    /// A selection still present in the rows is returned unchanged.
    func testReplacementKeepsPresentSelection() {
        let rows: [NavigableRow] = [.reminder("a"), .reminder("b")]
        XCTAssertEqual(ListNavigation.replacement(for: .reminder("b"), in: rows, previous: rows), .reminder("b"))
    }

    /// A vanished selection hands off to the row now at its old index.
    func testReplacementFollowsVacatedIndex() {
        let previous: [NavigableRow] = [.reminder("a"), .reminder("b"), .reminder("c")]
        let rows: [NavigableRow] = [.reminder("a"), .reminder("c")]  // "b" deleted
        XCTAssertEqual(ListNavigation.replacement(for: .reminder("b"), in: rows, previous: previous), .reminder("c"))
        // Deleting the last row lands on the new last row.
        let rows2: [NavigableRow] = [.reminder("a"), .reminder("b")]
        XCTAssertEqual(ListNavigation.replacement(for: .reminder("c"), in: rows2, previous: previous), .reminder("b"))
    }

    /// No rows left, or a selection that was never in `previous`, yields nil.
    func testReplacementClearsWhenListEmptiesOrSelectionUnknown() {
        XCTAssertNil(ListNavigation.replacement(for: .reminder("b"), in: [], previous: [.reminder("b")]))
        XCTAssertNil(ListNavigation.replacement(for: .reminder("x"),
                                                in: [.reminder("a")],
                                                previous: [.reminder("a"), .reminder("b")]))
    }

    // MARK: - KeyboardRouter.action: Escape chain

    func testRouterEscapeChain() {
        // Text field owns Escape.
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 53, heldKeyCodes: [53], context: context(textFieldFocused: true)),
            .none
        )
        // Selection clears before anything else.
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 53, heldKeyCodes: [53], context: context(hasSelection: true)),
            .clearSelection
        )
        // Selection beats search text in the chain.
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 53, heldKeyCodes: [53],
                                  context: context(searchFieldFocused: true, hasSelection: true, searchHasText: true)),
            .clearSelection
        )
        // Search text clears only while the search field is focused.
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 53, heldKeyCodes: [53],
                                  context: context(searchFieldFocused: true, searchHasText: true)),
            .clearSearchOrClose
        )
        // Search text with the field unfocused falls through to close.
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 53, heldKeyCodes: [53], context: context(searchHasText: true)),
            .closePopover
        )
        // Otherwise close.
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 53, heldKeyCodes: [53], context: context()),
            .closePopover
        )
    }

    // MARK: - KeyboardRouter.action: Tab matrix

    func testRouterTabMatrix() {
        // No shift: text field owns Tab; search → list mode; else → title.
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 48, heldKeyCodes: [48], context: context(textFieldFocused: true)),
            .none
        )
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 48, heldKeyCodes: [48], context: context(searchFieldFocused: true)),
            .enterListMode
        )
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 48, heldKeyCodes: [48], context: context()),
            .focusTitle
        )
        // Shift: search → notes; else → search.
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 48, heldKeyCodes: [56, 48], context: context(searchFieldFocused: true)),
            .focusNotes
        )
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 48, heldKeyCodes: [56, 48], context: context()),
            .focusSearch
        )
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 48, heldKeyCodes: [56, 48], context: context(textFieldFocused: true)),
            .focusSearch
        )
    }

    // MARK: - KeyboardRouter.action: ⌘F focus search

    func testRouterCommandFFocusesSearch() {
        // ⌘F is the default focus-search chord.
        XCTAssertEqual(KeyboardRouter.action(keyCode: 3, heldKeyCodes: [55, 3], context: context()), .focusSearch)
        XCTAssertEqual(KeyboardRouter.action(keyCode: 3, heldKeyCodes: [55, 3], context: context(textFieldFocused: true)), .focusSearch)
        XCTAssertEqual(KeyboardRouter.action(keyCode: 3, heldKeyCodes: [55, 3], context: context(searchFieldFocused: true)), .focusSearch)
        // F alone, ⌘ alone, and extra held keys do NOT match.
        XCTAssertEqual(KeyboardRouter.action(keyCode: 3, heldKeyCodes: [3], context: context()), .none)
        XCTAssertEqual(KeyboardRouter.action(keyCode: 3, heldKeyCodes: [55], context: context()), .none)
        XCTAssertEqual(KeyboardRouter.action(keyCode: 3, heldKeyCodes: [55, 3, 15], context: context()), .none)
    }

    func testRouterSlashUnmapped() {
        // "/" was the legacy focus-search default; the new table binds only ⌘F,
        // so "/" (keyCode 44) falls through everywhere.
        XCTAssertEqual(KeyboardRouter.action(keyCode: 44, heldKeyCodes: [44], context: context()), .none)
        XCTAssertEqual(KeyboardRouter.action(keyCode: 44, heldKeyCodes: [44], context: context(textFieldFocused: true)), .none)
        XCTAssertEqual(KeyboardRouter.action(keyCode: 44, heldKeyCodes: [44], context: context(searchFieldFocused: true)), .none)
    }

    // MARK: - KeyboardRouter.action: Enter / ⌘Enter / ⌫

    func testRouterRowActionsRequireSelectionAndNoFieldFocus() {
        // Return activates only with a selection and no field focused.
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 36, heldKeyCodes: [36], context: context(hasSelection: true)),
            .activateRow
        )
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 36, heldKeyCodes: [36], context: context()),
            .none
        )
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 36, heldKeyCodes: [36],
                                  context: context(textFieldFocused: true, hasSelection: true)),
            .none
        )
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 36, heldKeyCodes: [36],
                                  context: context(searchFieldFocused: true, hasSelection: true)),
            .none
        )
        // ⌘Enter opens.
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 36, heldKeyCodes: [55, 36], context: context(hasSelection: true)),
            .openRow
        )
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 36, heldKeyCodes: [55, 36], context: context()),
            .none
        )
        // ⌫ deletes.
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 51, heldKeyCodes: [51], context: context(hasSelection: true)),
            .deleteRow
        )
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 51, heldKeyCodes: [51],
                                  context: context(searchFieldFocused: true, hasSelection: true)),
            .none
        )
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 51, heldKeyCodes: [51], context: context()),
            .none
        )
    }

    // MARK: - KeyboardRouter.action: edit / snooze / undo

    func testRouterEditRequiresReminderAndNoFieldFocus() {
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 14, heldKeyCodes: [14],
                                  context: context(selectionIsReminder: true)),
            .editRow
        )
        // Completed reminders remain editable; completion only restricts snooze.
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 14, heldKeyCodes: [14],
                                  context: context(selectionIsReminder: true, selectionIsCompleted: true)),
            .editRow
        )
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 14, heldKeyCodes: [14],
                                  context: context(selectionIsHeader: true)),
            .none
        )
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 14, heldKeyCodes: [14],
                                  context: context(textFieldFocused: true, selectionIsReminder: true)),
            .none
        )
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 14, heldKeyCodes: [14],
                                  context: context(searchFieldFocused: true, selectionIsReminder: true)),
            .none
        )
    }

    func testRouterSnoozeRequiresIncompleteReminderAndNoFieldFocus() {
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 1, heldKeyCodes: [1],
                                  context: context(selectionIsReminder: true)),
            .snoozeRow
        )
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 1, heldKeyCodes: [1],
                                  context: context(selectionIsReminder: true, selectionIsCompleted: true)),
            .none
        )
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 1, heldKeyCodes: [1],
                                  context: context(selectionIsHeader: true)),
            .none
        )
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 1, heldKeyCodes: [1],
                                  context: context(textFieldFocused: true, selectionIsReminder: true)),
            .none
        )
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 1, heldKeyCodes: [1],
                                  context: context(searchFieldFocused: true, selectionIsReminder: true)),
            .none
        )
    }

    func testRouterUndoRequiresUndoEntryAndNoFieldFocus() {
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 6, heldKeyCodes: [55, 6], context: context(hasUndo: true)),
            .undo
        )
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 6, heldKeyCodes: [55, 6], context: context()),
            .none
        )
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 6, heldKeyCodes: [55, 6],
                                  context: context(textFieldFocused: true, hasUndo: true)),
            .none
        )
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 6, heldKeyCodes: [55, 6],
                                  context: context(searchFieldFocused: true, hasUndo: true)),
            .none
        )
        // Exact held-key matching remains in force for the new chord.
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 6, heldKeyCodes: [6], context: context(hasUndo: true)),
            .none
        )
    }

    // MARK: - KeyboardRouter.action: ←/→ and arrow/page/space guards

    func testRouterLeftOpensRecoveryWhenNoFieldFocused() {
        // ← is the default recovery shortcut; → remains unbound.
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 123, heldKeyCodes: [123], context: context(selectionIsHeader: true)),
            .toggleHeader
        )
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 124, heldKeyCodes: [124], context: context(selectionIsHeader: true)),
            .none
        )
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 123, heldKeyCodes: [123], context: context()),
            .toggleHeader
        )
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 124, heldKeyCodes: [124], context: context()),
            .none
        )
        // Guarded by no-field-focused.
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 123, heldKeyCodes: [123],
                                  context: context(textFieldFocused: true, selectionIsHeader: true)),
            .none
        )
    }

    func testRouterArrowsMoveSelectionOnlyWhenNoFieldFocused() {
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 125, heldKeyCodes: [125], context: context()),
            .moveSelection(1)
        )
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 126, heldKeyCodes: [126], context: context()),
            .moveSelection(-1)
        )
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 125, heldKeyCodes: [125], context: context(textFieldFocused: true)),
            .none
        )
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 126, heldKeyCodes: [126], context: context(searchFieldFocused: true)),
            .none
        )
    }

    func testRouterPageKeysMoveTen() {
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 121, heldKeyCodes: [121], context: context()),
            .moveSelection(10)
        )
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 116, heldKeyCodes: [116], context: context()),
            .moveSelection(-10)
        )
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 121, heldKeyCodes: [121], context: context(textFieldFocused: true)),
            .none
        )
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 116, heldKeyCodes: [116], context: context(searchFieldFocused: true)),
            .none
        )
    }

    func testRouterSpaceScrollsPage() {
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 49, heldKeyCodes: [49], context: context()),
            .scrollPage(1)
        )
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 49, heldKeyCodes: [56, 49], context: context()),
            .scrollPage(-1)
        )
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 49, heldKeyCodes: [49], context: context(textFieldFocused: true)),
            .none
        )
    }

    func testRouterUnmappedKeysAreNone() {
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 1, heldKeyCodes: [1], context: context()),
            .none
        )
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 0, heldKeyCodes: [55, 56, 0], context: context(hasSelection: true)),
            .none
        )
    }

    // MARK: - KeyboardRouter.action: custom bindings

    func testRouterCustomBindingOverridesDefault() {
        var bindings = DefaultBindings.all
        bindings[.moveDown] = KeyCombo([.key(38)]) // "J"
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 38, heldKeyCodes: [38], context: context(), bindings: bindings),
            .moveSelection(1)
        )
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 125, heldKeyCodes: [125], context: context(), bindings: bindings),
            .none
        )
    }

    func testRouterCustomBindingKeepsGuards() {
        var bindings = DefaultBindings.all
        bindings[.activateRow] = KeyCombo([.key(38)]) // "J"
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 38, heldKeyCodes: [38], context: context(hasSelection: true), bindings: bindings),
            .activateRow
        )
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 38, heldKeyCodes: [38], context: context(), bindings: bindings),
            .none
        )
    }

    func testRouterCustomBindingWithModifiers() {
        var bindings = DefaultBindings.all
        bindings[.openRow] = KeyCombo([.modifier(.command), .modifier(.option), .key(38)]) // ⌥⌘J
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 38, heldKeyCodes: [55, 58, 38],
                                  context: context(hasSelection: true), bindings: bindings),
            .openRow
        )
        // Same key with command only must not match the exact combo.
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 38, heldKeyCodes: [55, 38],
                                  context: context(hasSelection: true), bindings: bindings),
            .none
        )
    }

    func testRouterClosePopoverRebindKeepsEscapeChain() {
        var bindings = DefaultBindings.all
        bindings[.closePopover] = KeyCombo([.key(7)]) // "X"
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 7, heldKeyCodes: [7], context: context(hasSelection: true), bindings: bindings),
            .clearSelection
        )
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 7, heldKeyCodes: [7], context: context(), bindings: bindings),
            .closePopover
        )
        // Esc is no longer bound once .closePopover is rebound.
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 53, heldKeyCodes: [53], context: context(), bindings: bindings),
            .none
        )
    }

    func testRouterTabMatrixNotConfigurable() {
        var bindings = DefaultBindings.all
        bindings[.focusSearch] = KeyCombo([.key(48)]) // Tab
        // Tab matrix wins over any custom binding.
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 48, heldKeyCodes: [48], context: context(), bindings: bindings),
            .focusTitle
        )
    }

    // MARK: - KeyboardRouter.action: chord semantics

    func testRouterChordFiresOnlyOnExactHeldSet() {
        // ⌘↓ is not ↓: exact held-set equality.
        XCTAssertEqual(KeyboardRouter.action(keyCode: 125, heldKeyCodes: [125], context: context()), .moveSelection(1))
        XCTAssertEqual(KeyboardRouter.action(keyCode: 125, heldKeyCodes: [55, 125], context: context()), .none)
    }

    func testRouterChordCompletesOnLastKeyDown() {
        // Modifier pressed first, then the key: the key's keyDown completes the chord.
        var bindings = DefaultBindings.all
        bindings[.moveDown] = KeyCombo([.modifier(.command), .key(125)])
        XCTAssertEqual(KeyboardRouter.action(keyCode: 125, heldKeyCodes: [55, 125], context: context(), bindings: bindings), .moveSelection(1))
        XCTAssertEqual(KeyboardRouter.action(keyCode: 55, heldKeyCodes: [55, 125], context: context(), bindings: bindings), .none) // completing key must be in the chord — ⌘ keyDown doesn't fire it
    }
    func testRouterRecordedFullChordCompletesOnPlainKey() {
        let combo = KeyCombo.recorded(keyCode: 5, modifierFlags: [.command])!
        var bindings = DefaultBindings.all
        bindings[.moveDown] = combo

        XCTAssertEqual(
            KeyboardRouter.action(
                keyCode: 5,
                heldKeyCodes: combo.keySet,
                context: context(),
                bindings: bindings
            ),
            .moveSelection(1)
        )
    }

    func testRouterModifierOnlyBindingNeverMatches() {
        var bindings = DefaultBindings.all
        bindings[.moveDown] = KeyCombo([.modifier(.command)])

        XCTAssertEqual(
            KeyboardRouter.action(keyCode: ModifierKey.command.keyCode,
                                  heldKeyCodes: [ModifierKey.command.keyCode],
                                  context: context(), bindings: bindings),
            .none
        )
        XCTAssertEqual(
            KeyboardRouter.action(keyCode: 5,
                                  heldKeyCodes: [ModifierKey.command.keyCode, 5],
                                  context: context(), bindings: bindings),
            .none
        )
    }

    func testRouterEmptyComboDisabled() {
        var bindings = DefaultBindings.all
        bindings[.moveDown] = KeyCombo([])
        XCTAssertEqual(KeyboardRouter.action(keyCode: 125, heldKeyCodes: [125], context: context(), bindings: bindings), .none)
    }
}
