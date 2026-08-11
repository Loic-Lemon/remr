import AppKit
import EventKit
import SwiftUI

enum ReminderSection: String, CaseIterable {
    case overdue = "OVERDUE"
    case today = "TODAY"
    case later = "LATER"
}

/// The single-page popover: add a reminder on top, search below it,
/// and the unified reminder list beneath that.
struct MainView: View {
    @EnvironmentObject var store: ReminderStore
    @EnvironmentObject var settings: SettingsStore
    @ObservedObject private var filterStore = FilterStore.shared
    @State private var searchText = ""
    @State private var showGuide = false
    @State private var showSettings = false
    @State private var completedToast: String?
    @State private var toastTask: Task<Void, Never>?
    /// Both tabs collapse until clicked ("should not show by default").
    @State private var showRecentlyCompleted = false
    @State private var showRecentlyDeleted = false

    // Keyboard-first navigation (plan Step 4).
    @State private var selection: NavigableRow?
    @State private var titleFocusRequest = 0
    @State private var notesFocusRequest = 0
    @FocusState private var searchFocused: Bool
    @State private var monitor: Any?                 // NSEvent local monitor token
    @State private var popoverWindow: NSWindow?      // captured at install time
    @State private var scrollProxy: ScrollViewProxy?
    /// Keys currently held down (canonical codes) — the live chord being matched.
    @State private var heldKeys: Set<UInt16> = []
    /// The exact chord that last fired an action; nil = nothing fired yet.
    @State private var firedKeys: Set<UInt16>?

    /// All incomplete reminders, chronological (store's sort: due asc, nil last, title).
    private var allItems: [EKReminder] {
        store.allReminders.filter { !$0.isCompleted }
    }

    /// The active tag filter, lowercased without `#`; nil = no filter.
    private var activeFilter: String? {
        filterStore.tag
    }

    private var isFiltering: Bool {
        activeFilter != nil
    }

    /// Keep only reminders carrying the active tag, if any.
    private func filtered(_ items: [EKReminder]) -> [EKReminder] {
        guard let activeFilter else { return items }
        return items.filter { reminder in
            NaturalLanguageParser.containsTag(activeFilter,
                                              in: (reminder.title ?? "") + " " + (reminder.notes ?? ""))
        }
    }

    private var filteredItems: [EKReminder] {
        let byTag = filtered(allItems)
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return byTag }
        let query = SearchParser.parse(trimmed)
        let titles = Dictionary(uniqueKeysWithValues: store.reminderCalendars().map { ($0.calendarIdentifier, $0.title) })
        return byTag.filter { SearchParser.matches($0, query: query, calendarTitles: titles) }
    }

    /// Items not in overdue or today — belongs in LATER.
    private var laterItems: [EKReminder] {
        let overdueIDs = Set(store.overdue.map(\.calendarItemIdentifier))
        let todayIDs = Set(store.today.map(\.calendarItemIdentifier))
        return allItems.filter { !overdueIDs.contains($0.calendarItemIdentifier) && !todayIDs.contains($0.calendarItemIdentifier) }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Chip color for the active-filter pill (same palette as the row chips).
    private var filterColor: Color {
        TagStore.shared.color(for: activeFilter ?? "")
    }

    private var emptyStateText: String {
        if isSearching { return "No reminders match" }
        if let activeFilter { return "No reminders with #\(activeFilter)" }
        return "All caught up"
    }

    private var sections: [(ReminderSection, [EKReminder])] {
        ReminderSection.allCases.compactMap { section in
            let items: [EKReminder]
            switch section {
            case .overdue: items = filtered(store.overdue)
            case .today: items = filtered(store.today)
            case .later: items = filtered(laterItems)
            }
            return items.isEmpty ? nil : (section, items)
        }
    }

    /// The flat navigable order, mirroring listArea's render order exactly,
    /// so the arrow-key selection can never drift from what is on screen.
    private var navRows: [NavigableRow] {
        ListNavigation.rows(sections: sections,
                            filtered: filteredItems,
                            isSearching: isSearching,
                            completed: store.completedReminders,
                            showCompleted: showRecentlyCompleted,
                            deleted: store.recentlyDeleted,
                            showDeleted: showRecentlyDeleted,
                            hidesTabs: isFiltering)
    }

    var body: some View {
        Group {
            if showSettings {
                SettingsView(onClose: { showSettings = false })
            } else {
                VStack(spacing: 0) {
                    NewReminderView(titleFocusRequest: titleFocusRequest,
                                    notesFocusRequestExternal: notesFocusRequest,
                                    onTabForward: { searchFocused = true },
                                    onTabBackFromTitle: { execute(.enterListMode) },
                                    onEscape: handleEscape)
                    searchRow
                    Divider()
                    listArea
                }
            }
        }
        .onAppear {
            // The WindowProbe background is authoritative (fires with the real
            // popover window) and must not be overwritten by a stale keyWindow
            // (e.g. the standalone Settings window being key).
            if popoverWindow == nil { popoverWindow = NSApp.keyWindow }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
                // MainView is a struct; capture its value copy — @State/@FocusState
                // setters are nonmutating, so mutations reach shared storage.
                // While the settings recorder is capturing, defer every event so
                // the recorder's own (later-registered) monitor sees them first.
                // NSApp.keyWindow is still nil when onAppear runs (the popover
                // window is only made key after show()), so the window identity
                // comes from the WindowProbe background; self-heal any leftover
                // nil from the first key event of the session.
                if settings.isCapturing { return event }                     // while capturing, defer to the recorder's monitor
                // The inline Settings view replaces this whole pane, but the
                // monitor stays installed (it lives on the Group); routing keys
                // here would fire list actions against the hidden list (Enter
                // completes a reminder, ⌫ deletes one, Esc closes the popover).
                if showSettings { return event }
                guard let eventWindow = event.window else { return event }
                if popoverWindow == nil { popoverWindow = eventWindow }
                guard eventWindow === popoverWindow else { return event }   // only route the main popover's keys
                if event.type == .flagsChanged {
                    // Modifier presses arrive as flagsChanged, never keyDown — sync
                    // heldKeys with the current modifier state (canonical codes) so
                    // modifier chords like ⌘F match when the plain key lands.
                    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    if flags.contains(.command) { heldKeys.insert(ModifierKey.command.keyCode) } else { heldKeys.remove(ModifierKey.command.keyCode) }
                    if flags.contains(.shift) { heldKeys.insert(ModifierKey.shift.keyCode) } else { heldKeys.remove(ModifierKey.shift.keyCode) }
                    if flags.contains(.option) { heldKeys.insert(ModifierKey.option.keyCode) } else { heldKeys.remove(ModifierKey.option.keyCode) }
                    if flags.contains(.control) { heldKeys.insert(ModifierKey.control.keyCode) } else { heldKeys.remove(ModifierKey.control.keyCode) }
                    if heldKeys != firedKeys { firedKeys = nil }
                    return event
                }
                let firstResponder = popoverWindow?.firstResponder
                let ctx = KeyboardContext(
                    textFieldFocused: firstResponder is EnterSubmitTextView,
                    searchFieldFocused: firstResponder is NSTextField,
                    selectionIsHeader: {
                        if case .tabHeader = selection { return true }
                        return false
                    }(),
                    hasSelection: selection != nil,
                    searchHasText: !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                if event.type == .keyUp {
                    let canonical = ModifierKey.canonicalKeyCode(for: event.keyCode) ?? event.keyCode
                    heldKeys.remove(canonical)
                    syncModifiers(from: event.modifierFlags)
                    if heldKeys != firedKeys { firedKeys = nil }
                    return event
                }
                let canonical = ModifierKey.canonicalKeyCode(for: event.keyCode) ?? event.keyCode
                heldKeys.insert(canonical)
                syncModifiers(from: event.modifierFlags)
                // Swallow repeats of an already-fired chord so holding a key
                // doesn't re-fire the action; unfired repeats route as before.
                if event.isARepeat && heldKeys == firedKeys { return nil }
                // Shift+Tab with a text field focused: let the text view handle
                // it (insertBacktab → onFocusBack) so Shift+Tab walks backwards
                // (notes → title → list mode). The router maps this case to
                // .focusSearch, which would skip the backwards step entirely
                // (the onFocusBack wiring in NewReminderView is dead otherwise).
                if event.keyCode == 48, heldKeys.contains(ModifierKey.shift.keyCode),
                   firstResponder is EnterSubmitTextView {
                    firedKeys = heldKeys
                    return event
                }
                switch KeyboardRouter.action(keyCode: event.keyCode,
                                             heldKeyCodes: heldKeys,
                                             context: ctx,
                                             bindings: settings.bindings) {
                case .none: return event
                case let action:
                    firedKeys = heldKeys
                    execute(action)
                    return nil
                }
            }
        }
        .onDisappear {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            selection = nil
            popoverWindow = nil
            heldKeys = []
            firedKeys = nil
        }
        .background(WindowProbe { popoverWindow = $0 })
    }

    /// Search field (gray rounded capsule) + the (i) guide button.
    private var searchRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onChange(of: searchText) { _ in selection = nil }
                    .onChange(of: filterStore.tag) { _ in selection = nil }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(AppPalette.fieldFill))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(AppPalette.fieldStroke, lineWidth: 1))

            if let activeFilter {
                HStack(spacing: 4) {
                    Text("#\(activeFilter)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(filterColor)
                    Button {
                        filterStore.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(filterColor)
                    }
                    .buttonStyle(.plain)
                    .help("Clear tag filter")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(filterColor.opacity(0.16)))
                .overlay(Capsule().strokeBorder(filterColor.opacity(0.45), lineWidth: 1))
                .help("Filtered by #\(activeFilter)")
            }

            Button {
                showGuide = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("How to use remr")
            .popover(isPresented: $showGuide, arrowEdge: .bottom) {
                GuideView()
            }

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var listArea: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                ScrollViewReader { proxy in
                    LazyVStack(spacing: 0) {
                        if filteredItems.isEmpty {
                            VStack(spacing: 6) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.tertiary)
                                Text(emptyStateText)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 48)
                        } else if isSearching {
                            ForEach(filteredItems, id: \.calendarItemIdentifier) { reminder in
                                ReminderRowView(reminder: reminder,
                                                isSelected: selection == .reminder(reminder.calendarItemIdentifier)) { completed in
                                    showCompletedToast(completed.title)
                                }
                                .id(rowID(.reminder(reminder.calendarItemIdentifier)))
                                Divider()
                                    .padding(.leading, 12)
                            }
                        } else {
                            ForEach(sections, id: \.0) { section, items in
                                Text(section.rawValue)
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.top, 12)
                                    .padding(.bottom, 4)
                                ForEach(items, id: \.calendarItemIdentifier) { reminder in
                                    ReminderRowView(reminder: reminder,
                                                    isSelected: selection == .reminder(reminder.calendarItemIdentifier)) { completed in
                                        showCompletedToast(completed.title)
                                    }
                                    .id(rowID(.reminder(reminder.calendarItemIdentifier)))
                                }
                                Divider()
                                    .padding(.leading, 12)
                            }
                        }
                        // Both tabs live outside the empty-state branch so they
                        // pop up even when nothing else is in the list; hidden
                        // while searching or tag-filtering.
                        if !isSearching && !isFiltering {
                            if !store.completedReminders.isEmpty {
                                recentlyCompletedTab
                            }
                            if !store.recentlyDeleted.isEmpty {
                                recentlyDeletedTab
                            }
                        }
                    }
                    .onAppear { scrollProxy = proxy }
                }
            }
            if let completedToast {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(completedToast)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.callout.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(AppPalette.surface))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                .padding(.bottom, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: completedToast)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Collapsed-by-default tab header shared by both recovery lists.
    private func tabHeader(_ title: String, count: Int, isOpen: Bool,
                           isSelected: Bool, toggle: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(duration: 0.3)) {
                toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.semibold))
                Text(title)
                    .font(.caption.bold())
                Spacer()
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.16))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Completed reminders, newest first, capped at the 5 most recent.
    private var recentlyCompletedTab: some View {
        VStack(spacing: 0) {
            tabHeader("Recently Completed", count: min(store.completedReminders.count, 5),
                      isOpen: showRecentlyCompleted,
                      isSelected: selection == .tabHeader(.completed)) {
                showRecentlyCompleted.toggle()
            }
            .id(rowID(.tabHeader(.completed)))
            if showRecentlyCompleted {
                ForEach(store.completedReminders.prefix(5), id: \.calendarItemIdentifier) { reminder in
                    ReminderRowView(reminder: reminder,
                                    isSelected: selection == .reminder(reminder.calendarItemIdentifier)) { completed in
                        showCompletedToast(completed.title)
                    }
                    .id(rowID(.reminder(reminder.calendarItemIdentifier)))
                }
                Divider()
                    .padding(.leading, 12)
            }
        }
    }

    /// Shadow-copied deletions, newest first, capped at the 5 most recent.
    private var recentlyDeletedTab: some View {
        VStack(spacing: 0) {
            tabHeader("Recently Deleted", count: store.recentlyDeleted.count,
                      isOpen: showRecentlyDeleted,
                      isSelected: selection == .tabHeader(.deleted)) {
                showRecentlyDeleted.toggle()
            }
            .id(rowID(.tabHeader(.deleted)))
            if showRecentlyDeleted {
                ForEach(store.recentlyDeleted.prefix(5)) { deleted in
                    DeletedReminderRow(deleted: deleted,
                                       isSelected: selection == .deleted(deleted.id))
                        .id(rowID(.deleted(deleted.id)))
                }
                Divider()
                    .padding(.leading, 12)
            }
        }
    }

    private func showCompletedToast(_ title: String) {
        completedToast = "Completed \"\(title)\" today"
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            completedToast = nil
        }
    }

    /// Stable id used by ScrollViewReader.scrollTo for a navigable row.
    private func rowID(_ row: NavigableRow) -> String {
        switch row {
        case .reminder(let id): return "r:\(id)"
        case .deleted(let uuid): return "d:\(uuid)"
        case .tabHeader(let kind): return "h:\(kind.rawValue)"
        }
    }

    /// Reconstruct modifier membership from the event's flags (post-change
    /// state), so modifier chords like ⌘F match even if flagsChanged never
    /// reaches a local monitor. Idempotent with the flagsChanged branch (Set).
    private func syncModifiers(from flags: NSEvent.ModifierFlags) {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) { heldKeys.insert(ModifierKey.command.keyCode) } else { heldKeys.remove(ModifierKey.command.keyCode) }
        if flags.contains(.shift) { heldKeys.insert(ModifierKey.shift.keyCode) } else { heldKeys.remove(ModifierKey.shift.keyCode) }
        if flags.contains(.option) { heldKeys.insert(ModifierKey.option.keyCode) } else { heldKeys.remove(ModifierKey.option.keyCode) }
        if flags.contains(.control) { heldKeys.insert(ModifierKey.control.keyCode) } else { heldKeys.remove(ModifierKey.control.keyCode) }
    }

    /// Runs a routed key action against the list selection (plan Step 4).
    private func execute(_ action: KeyAction) {
        switch action {
        case .none:
            break
        case .moveSelection(let delta):
            let rows = navRows
            guard let idx = ListNavigation.move(fromIndex: ListNavigation.selectedIndex(selection, in: rows),
                                                by: delta, count: rows.count),
                  idx < rows.count else { return }
            selection = rows[idx]
            withAnimation {
                scrollProxy?.scrollTo(rowID(rows[idx]), anchor: .center)
            }
        case .scrollPage(let delta):
            // The plan's scrollTo(_ anchor: UnitPoint) overload is macOS 14+;
            // on the macOS 13 floor, page by anchoring to the list's ends.
            let rows = navRows
            guard let first = rows.first, let last = rows.last else { return }
            withAnimation {
                scrollProxy?.scrollTo(rowID(delta < 0 ? first : last), anchor: delta < 0 ? .top : .bottom)
            }
        case .toggleHeader:
            toggleHeader()
        case .clearSelection:
            selection = nil
        case .focusSearch:
            searchFocused = true
        case .focusTitle:
            titleFocusRequest += 1
        case .focusNotes:
            notesFocusRequest += 1
        case .enterListMode:
            popoverWindow?.makeFirstResponder(nil)
            if selection == nil { selection = navRows.first }
        case .clearSearchOrClose:
            searchText.isEmpty ? closePopover() : (searchText = "")
        case .closePopover:
            closePopover()
        case .activateRow:
            switch selection {
            case .reminder(let id):
                guard let reminder = (store.allReminders + store.completedReminders).first(where: { $0.calendarItemIdentifier == id }) else { return }
                Task { await store.toggleCompletion(reminder); if reminder.isCompleted { showCompletedToast(reminder.title) } }
            case .deleted(let uuid):
                guard let deleted = store.recentlyDeleted.first(where: { $0.id == uuid }) else { return }
                Task { await store.restore(deleted) }
            case .tabHeader:
                toggleHeader()
            case nil:
                break
            }
        case .openRow:
            if case .reminder(let id) = selection,
               let reminder = (store.allReminders + store.completedReminders).first(where: { $0.calendarItemIdentifier == id }) {
                store.openInReminders(reminder)
            }
        case .deleteRow:
            switch selection {
            case .reminder(let id):
                guard let reminder = (store.allReminders + store.completedReminders).first(where: { $0.calendarItemIdentifier == id }) else { return }
                Task { await store.deleteReminder(reminder) }
            case .deleted(let uuid):
                guard let deleted = store.recentlyDeleted.first(where: { $0.id == uuid }) else { return }
                store.deleteForever(deleted)
            case .tabHeader:
                break
            case nil:
                break
            }
        }
    }

    /// ←/→ (or Enter) on a selected recovery header toggles its expansion —
    /// mirrors tabHeader's button action.
    private func toggleHeader() {
        withAnimation(.spring(duration: 0.3)) {
            switch selection {
            case .tabHeader(.completed): showRecentlyCompleted.toggle()
            case .tabHeader(.deleted): showRecentlyDeleted.toggle()
            default: break
            }
        }
    }

    private func closePopover() {
        AppDelegate.instance?.closePopover()
    }

    /// Escape chain for the text fields: clear the selection first, else close.
    private func handleEscape() {
        if selection != nil {
            selection = nil
        } else {
            closePopover()
        }
    }
}

/// Deterministic popover-window capture: `NSApp.keyWindow` is still nil when
/// SwiftUI fires `onAppear` (the popover window is only made key after
/// `show()`), so the monitor instead learns its window from this probe's
/// `viewDidMoveToWindow`, which fires with the real window on attach.
private struct WindowProbe: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> ProbeView {
        ProbeView(onWindow: onWindow)
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {}
}

private final class ProbeView: NSView {
    private let onWindow: (NSWindow?) -> Void

    init(onWindow: @escaping (NSWindow?) -> Void) {
        self.onWindow = onWindow
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { onWindow(window) }   // nil moves handled by onDisappear
    }
}
