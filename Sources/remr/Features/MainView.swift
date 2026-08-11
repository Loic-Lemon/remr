import AppKit
import EventKit
import SwiftUI

/// The single-page popover: add a reminder on top, search below it,
/// and the unified reminder list beneath that.
struct MainView: View {
    @EnvironmentObject var store: ReminderStore
    @EnvironmentObject var settings: SettingsStore
    @ObservedObject private var filterStore = FilterStore.shared
    @State private var searchText = ""
    @State private var showGuide = false
    @State private var showRecovery = false
    @State private var showSettings = false
    @State private var bulkInput: String?
    @State private var editingReminder: EKReminder?
    @State private var snoozingReminder: EKReminder?
    @State private var snoozeShowingPicker = false
    @State private var confirmDeleteForever = false
    @State private var pendingDeleteForever: DeletedReminder?
    @State private var actionToast: ActionToastState?
    @State private var actionToastTask: Task<Void, Never>?

    private struct ActionToastState {
        let message: String
        let actionTitle: String?
        let action: (() -> Void)?
        let duration: TimeInterval
    }

    private enum UndoEntry {
        case completion(reminderID: String, wasCompleted: Bool)
        case deletion(snapshot: DeletedReminder)
    }

    @State private var undoEntry: UndoEntry?
    @State private var knownReminderIDs: Set<String> = []

    // Keyboard-first navigation (plan Step 4).
    @State private var selection: NavigableRow?
    @State private var titleFocusRequest = 0
    @State private var showTagFilter = false
    @State private var showTagManager = false
    @State private var notesFocusRequest = 0
    @FocusState private var searchFocused: Bool
    @State private var monitor: Any?                 // NSEvent local monitor token
    @State private var popoverWindow: NSWindow?      // captured at install time
    @State private var scrollProxy: ScrollViewProxy?
    /// Keys currently held down (canonical codes) — the live chord being matched.
    @State private var heldKeys: Set<UInt16> = []

    /// Whether the composer currently shows description/parse content. Drives
    /// the slide animation of the composer layer over the fixed list layer.
    @State private var composerExpanded = false

    /// Height of the collapsed composer block (editor + search row), reserved
    /// in the fixed list layer so expansion overlays the list instead of
    /// pushing it down.
    @State private var reservedTopHeight: CGFloat = 0
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

    /// Every incomplete reminder bucketed into the pinned ongoing section or
    /// chronological sections; tag filter applied per section, empty sections
    /// dropped.
    private var sections: [(ReminderSection, [EKReminder])] {
        let bounds = ReminderSection.bounds()
        var grouped: [ReminderSection: [EKReminder]] = [:]
        for item in allItems {
            let due = item.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
            grouped[ReminderSection.section(for: due,
                                            ongoing: NaturalLanguageParser.isOngoing(title: item.title,
                                                                                     notes: item.notes),
                                            bounds: bounds), default: []].append(item)
        }
        return ReminderSection.allCases.compactMap { section in
            let items = filtered(grouped[section] ?? [])
            return items.isEmpty ? nil : (section, items)
        }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Chip color for the active-filter pill (same palette as the row chips).
    private var filterColor: Color {
        TagStore.shared.color(for: activeFilter ?? "")
    }

    /// Every tag currently found in reminders (lowercased, sorted) — the tag
    /// dropdown's list.
    private var allTags: [String] {
        store.allTags()
    }

    private var emptyStateText: String {
        if isSearching { return "No reminders match" }
        if let activeFilter { return "No reminders with #\(activeFilter)" }
        return "All caught up"
    }

    private var reminderIDs: Set<String> {
        Set((store.allReminders + store.completedReminders).map(\.calendarItemIdentifier))
    }

    /// The flat navigable order, mirroring listArea's render order exactly,
    /// so the arrow-key selection can never drift from what is on screen.
    private var navRows: [NavigableRow] {
        ListNavigation.rows(sections: sections,
                            filtered: filteredItems,
                            isSearching: isSearching,
                            completed: [],
                            showCompleted: false,
                            deleted: [],
                            showDeleted: false,
                            hidesTabs: isFiltering)
    }

    var body: some View {
        Group {
            if showSettings {
                SettingsView(onClose: { showSettings = false })
            } else if let editingReminder {
                ReminderEditView(reminder: editingReminder,
                                 onCancel: { self.editingReminder = nil },
                                 onSaved: { identifier in
                                     self.undoEntry = nil
                                     self.selection = .reminder(identifier)
                                     self.editingReminder = nil
                                     showActionToast(message: "Saved reminder", duration: 2.5)
                                 })
            } else if let bulkInput {
                BulkReminderPreview(text: bulkInput,
                                     onCancel: { self.bulkInput = nil },
                                     onDone: {
                                         self.bulkInput = nil
                                         self.undoEntry = nil
                                     })
            } else {
                VStack(spacing: 0) {
                    // The composer expands over the list instead of pushing it:
                    // the list layer stays fixed (reserving the collapsed top
                    // block height), while the composer layer slides down over
                    // it, its glass surface covering the items beneath.
                    ZStack(alignment: .top) {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: reservedTopHeight)
                            Divider()
                            listArea
                        }
                        VStack(spacing: 0) {
                            VStack(spacing: 0) {
                                NewReminderView(titleFocusRequest: titleFocusRequest,
                                                notesFocusRequestExternal: notesFocusRequest,
                                                onTabForward: { searchFocused = true },
                                                onTabBackFromTitle: { execute(.enterListMode) },
                                                onEscape: handleEscape,
                                                onBulkPreview: {
                                                    self.undoEntry = nil
                                                    self.bulkInput = $0
                                                },
                                                onEntryPresenceChange: { composerExpanded = $0 })
                                searchRow
                            }
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(key: TopBlockHeightKey.self,
                                                           value: geo.size.height)
                                }
                            )
                            Color.clear
                                .frame(maxHeight: .infinity)
                                .allowsHitTesting(false)
                        }
                        .animation(.easeInOut(duration: 0.2), value: composerExpanded)
                    }
                    .onPreferenceChange(TopBlockHeightKey.self) { height in
                        // Reserved space tracks the collapsed height: the first
                        // report (before any expansion) is the collapsed layout,
                        // and expansions only ever grow from there.
                        if reservedTopHeight == 0 || height < reservedTopHeight {
                            reservedTopHeight = height
                        }
                    }
                }
            }
        }
        .onAppear {
            if popoverWindow == nil { popoverWindow = NSApp.keyWindow }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
                if settings.isCapturing { return event }
                if showSettings || editingReminder != nil || bulkInput != nil || snoozingReminder != nil {
                    return event
                }
                guard let eventWindow = event.window else { return event }
                if popoverWindow == nil { popoverWindow = eventWindow }
                guard eventWindow === popoverWindow else { return event }
                if event.type == .flagsChanged {
                    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    if flags.contains(.command) { heldKeys.insert(ModifierKey.command.keyCode) } else { heldKeys.remove(ModifierKey.command.keyCode) }
                    if flags.contains(.shift) { heldKeys.insert(ModifierKey.shift.keyCode) } else { heldKeys.remove(ModifierKey.shift.keyCode) }
                    if flags.contains(.option) { heldKeys.insert(ModifierKey.option.keyCode) } else { heldKeys.remove(ModifierKey.option.keyCode) }
                    if flags.contains(.control) { heldKeys.insert(ModifierKey.control.keyCode) } else { heldKeys.remove(ModifierKey.control.keyCode) }
                    if heldKeys != firedKeys { firedKeys = nil }
                    return event
                }
                let firstResponder = popoverWindow?.firstResponder
                let selectedReminder: EKReminder? = {
                    guard case .reminder(let id) = selection else { return nil }
                    return (store.allReminders + store.completedReminders)
                        .first { $0.calendarItemIdentifier == id }
                }()
                let ctx = KeyboardContext(
                    textFieldFocused: firstResponder is EnterSubmitTextView,
                    searchFieldFocused: firstResponder is NSTextField,
                    selectionIsHeader: {
                        if case .tabHeader = selection { return true }
                        return false
                    }(),
                    hasSelection: selection != nil,
                    searchHasText: !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    selectionIsReminder: selectedReminder != nil,
                    selectionIsCompleted: selectedReminder?.isCompleted ?? false,
                    hasUndo: undoEntry != nil
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
                if event.isARepeat && heldKeys == firedKeys { return nil }
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
        .onChange(of: reminderIDs) { ids in
            if !knownReminderIDs.isEmpty && !ids.isSubset(of: knownReminderIDs) {
                undoEntry = nil
            }
            knownReminderIDs = ids
        }
        .onDisappear {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            selection = nil
            popoverWindow = nil
            heldKeys = []
            firedKeys = nil
            actionToastTask?.cancel()
        }
        .background(WindowProbe { popoverWindow = $0 })
        .confirmationDialog("Delete Forever?", isPresented: $confirmDeleteForever,
                            titleVisibility: .visible) {
            Button("Delete Forever", role: .destructive) {
                guard let deleted = pendingDeleteForever else { return }
                store.deleteForever(deleted)
                pendingDeleteForever = nil
                undoEntry = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteForever = nil
            }
        } message: {
            Text("This cannot be undone.")
        }
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
            .liquidGlassField()
            TagFilterMenu(allTags: allTags,
                          isPresented: $showTagFilter,
                          onManage: { showTagManager = true })
            .popover(isPresented: $showTagManager, arrowEdge: .bottom) {
                TagManagerView()
                    .environmentObject(store)
            }

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
                .liquidGlassCapsule(tint: filterColor)
                .help("Filtered by #\(activeFilter)")
            }
            Button {
                showRecovery.toggle()
            } label: {
                Image(systemName: "archivebox")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Recently completed and deleted")
            .background {
                FastPopoverPresenter(
                    isPresented: showRecovery,
                    content: AnyView(
                        RecoveryPopoverView(
                            onClose: { showRecovery = false },
                            onToggleCompletion: performToggleCompletion,
                            onDelete: performDelete,
                            onEdit: { editingReminder = $0 },
                            onDuplicate: duplicateReminder,
                            onMoveToList: moveReminder,
                            onCopyTitle: copyReminderTitle,
                            onRestored: handleRestored,
                            onDeletedForever: handleDeletedForever
                        )
                        .environmentObject(store)
                    ),
                    onDismiss: { showRecovery = false }
                )
            }


            Button {
                showGuide.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("How to use remr")
            .background {
                FastPopoverPresenter(
                    isPresented: showGuide,
                    content: AnyView(GuideView(onClose: { showGuide = false })),
                    onDismiss: { showGuide = false }
                )
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
        // One continuous glass panel with the editor above: the surface spans
        // the full padded row (abutting the editor's glass) and full content
        // width, so when the composer expands the search row glides down with
        // it and reads as the same surface — blurring the list items it passes
        // over — rather than a transparent row showing raw items through gaps.
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(AppPalette.surfaceFill)
        .padding(.horizontal, 12)
        .zIndex((showTagFilter || showRecovery) ? 10 : 0)
    }

    private var syncFooter: some View {
        TimelineView(.periodic(from: .now, by: 10)) { context in
            Group {
                if let lastSyncDate = store.lastSyncDate {
                    Text(syncStatusLabel(from: lastSyncDate, now: context.date))
                } else {
                    Text("Updating reminders…")
                }
            }
            .font(.system(size: 10))
            .italic()
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
        }
    }

    private func syncStatusLabel(from date: Date, now: Date) -> String {
        let elapsed = max(0, now.timeIntervalSince(date))
        switch elapsed {
        case ..<10: return "Updated just now"
        case ..<30: return "Updated moments ago"
        case ..<60: return "Updated less than a minute ago"
        case ..<120: return "Updated about a minute ago"
        case ..<300: return "Updated a few minutes ago"
        case ..<600: return "Updated about 10 minutes ago"
        case ..<1_800: return "Updated about half an hour ago"
        case ..<3_600: return "Updated about an hour ago"
        case ..<7_200: return "Updated about 2 hours ago"
        case ..<21_600: return "Updated earlier today"
        case ..<86_400: return "Updated today"
        case ..<172_800: return "Updated yesterday"
        case ..<604_800: return "Updated this week"
        default: return "Updated over a week ago"
        }
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
                                                isSelected: selection == .reminder(reminder.calendarItemIdentifier),
                                                onSelect: { selection = .reminder(reminder.calendarItemIdentifier) },
                                                onToggleCompletion: performToggleCompletion,
                                                onDelete: performDelete,
                                                onEdit: { editingReminder = $0 },
                                                onSnooze: beginSnooze,
                                                onDuplicate: duplicateReminder,
                                                onMoveToList: moveReminder,
                                                onCopyTitle: copyReminderTitle)
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
                                                    isSelected: selection == .reminder(reminder.calendarItemIdentifier),
                                                    onSelect: { selection = .reminder(reminder.calendarItemIdentifier) },
                                                    onToggleCompletion: performToggleCompletion,
                                                    onDelete: performDelete,
                                                    onEdit: { editingReminder = $0 },
                                                    onSnooze: beginSnooze,
                                                    onDuplicate: duplicateReminder,
                                                    onMoveToList: moveReminder,
                                                    onCopyTitle: copyReminderTitle)
                                    .id(rowID(.reminder(reminder.calendarItemIdentifier)))
                                }
                                Divider()
                                    .padding(.leading, 12)
                            }
                        }
                    }
                    .onAppear { scrollProxy = proxy }
                }
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                syncFooter
            }
            if let toast = actionToast {
                ActionToast(message: toast.message,
                            actionTitle: toast.actionTitle,
                            action: toast.action)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: actionToast?.message)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .popover(isPresented: Binding(get: { snoozingReminder != nil },
                                      set: { presented in
                                          if !presented { closeSnooze() }
                                      }), arrowEdge: .bottom) {
            if let reminder = snoozingReminder {
                if snoozeShowingPicker {
                    SnoozeDatePickerView(initialDate: dueDate(of: reminder) ?? defaultSnoozeDate(),
                                         initialHasTime: hasTime(of: reminder),
                                         onCancel: closeSnooze,
                                         onSave: saveCustomSnooze)
                } else {
                    SnoozeMenu(onChoice: applySnooze,
                               onCustom: { snoozeShowingPicker = true },
                               onClear: { saveSnooze(reminder, until: nil, hasTime: false, label: "cleared") })
                }
            }
        }
    }


    private func performToggleCompletion(_ reminder: EKReminder) {
        Task { @MainActor in
            do {
                let result = try await store.toggleCompletion(reminder)
                undoEntry = .completion(reminderID: reminder.calendarItemIdentifier,
                                        wasCompleted: result.wasCompleted)
                let verb = result.isCompleted ? "Completed" : "Restored"
                let title = reminder.title ?? "Reminder"
                showActionToast(message: "\(verb) \"\(title)\"",
                                actionTitle: "Undo",
                                action: { performUndo() },
                                duration: 5.0)
            } catch {
                showActionToast(message: error.localizedDescription, duration: 2.5)
            }
        }
    }

    private func performDelete(_ reminder: EKReminder) {
        Task { @MainActor in
            do {
                let snapshot = try await store.deleteReminder(reminder)
                undoEntry = snapshot.map { .deletion(snapshot: $0) }
                let undoAction: (() -> Void)? = snapshot == nil ? nil : { performUndo() }
                let title = reminder.title ?? "Reminder"
                showActionToast(message: "Deleted \"\(title)\"",
                                actionTitle: snapshot == nil ? nil : "Undo",
                                action: undoAction,
                                duration: snapshot == nil ? 2.5 : 5.0)
            } catch {
                showActionToast(message: error.localizedDescription, duration: 2.5)
            }
        }
    }
    private func handleRestored(_ deleted: DeletedReminder) {
        undoEntry = nil
        showActionToast(message: "Restored \"\(deleted.title)\"", duration: 2.5)
    }

    private func handleDeletedForever(_ deleted: DeletedReminder) {
        undoEntry = nil
    }

    private func copyReminderTitle(_ reminder: EKReminder) {
        let title = reminder.title ?? ""
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(title, forType: .string)
        showActionToast(message: "Copied title", duration: 2.0)
    }

    private func duplicateReminder(_ reminder: EKReminder) {
        Task { @MainActor in
            do {
                let duplicate = try await store.duplicate(reminder)
                selection = .reminder(duplicate.calendarItemIdentifier)
                showActionToast(message: "Duplicated \"\(reminder.title ?? "Reminder")\"", duration: 2.5)
            } catch {
                showActionToast(message: error.localizedDescription, duration: 2.5)
            }
        }
    }

    private func moveReminder(_ reminder: EKReminder, _ calendarIdentifier: String?) {
        let destination = calendarIdentifier.flatMap { identifier in
            store.reminderCalendars().first { $0.calendarIdentifier == identifier }?.title
        } ?? "Default list"
        Task { @MainActor in
            do {
                try await store.moveToList(reminder, calendarIdentifier: calendarIdentifier)
                showActionToast(message: "Moved to \(destination)", duration: 2.5)
            } catch {
                showActionToast(message: error.localizedDescription, duration: 2.5)
            }
        }
    }


    private func showActionToast(message: String,
                                 actionTitle: String? = nil,
                                 action: (() -> Void)? = nil,
                                 duration: TimeInterval) {
        actionToastTask?.cancel()
        actionToast = ActionToastState(message: message,
                                       actionTitle: actionTitle,
                                       action: action,
                                       duration: duration)
        let expiresUndo = actionTitle != nil
        actionToastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            actionToast = nil
            if expiresUndo { undoEntry = nil }
        }
    }

    private func performUndo() {
        guard let entry = undoEntry else { return }
        undoEntry = nil
        Task { @MainActor in
            switch entry {
            case .completion(let reminderID, let wasCompleted):
                guard let reminder = store.reminder(withIdentifier: reminderID) else {
                    showActionToast(message: "Reminder no longer exists", duration: 2.5)
                    return
                }
                if reminder.isCompleted != wasCompleted {
                    do {
                        _ = try await store.toggleCompletion(reminder)
                    } catch {
                        showActionToast(message: error.localizedDescription, duration: 2.5)
                        return
                    }
                }
                let title = reminder.title ?? "Reminder"
                showActionToast(message: "Undid \"\(title)\"", duration: 2.5)
            case .deletion(let snapshot):
                do {
                    try await store.restore(snapshot)
                    showActionToast(message: "Restored \"\(snapshot.title)\"", duration: 2.5)
                } catch {
                    showActionToast(message: error.localizedDescription, duration: 2.5)
                }
            }
        }
    }

    private func beginSnooze(_ reminder: EKReminder) {
        guard !reminder.isCompleted else { return }
        snoozeShowingPicker = false
        snoozingReminder = reminder
    }

    private func closeSnooze() {
        snoozeShowingPicker = false
        snoozingReminder = nil
    }

    private func applySnooze(_ choice: SnoozeChoice) {
        guard let reminder = snoozingReminder else { return }
        guard let result = SnoozeCalculator.date(for: choice, now: Date(), calendar: .current) else {
            showActionToast(message: "Couldn't calculate snooze date", duration: 2.5)
            return
        }
        saveSnooze(reminder, until: result.date, hasTime: result.hasTime,
                   label: result.date.formatted(date: .abbreviated, time: .shortened))
    }

    private func saveCustomSnooze(_ date: Date?, _ hasTime: Bool) {
        guard let reminder = snoozingReminder else { return }
        saveSnooze(reminder, until: date, hasTime: hasTime,
                   label: date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "cleared")
    }

    private func saveSnooze(_ reminder: EKReminder, until date: Date?, hasTime: Bool, label: String) {
        Task { @MainActor in
            do {
                try await store.snooze(reminder, until: date, hasTime: hasTime)
                undoEntry = nil
                closeSnooze()
                let title = reminder.title ?? "Reminder"
                showActionToast(message: "Snoozed \"\(title)\" until \(label)", duration: 2.5)
            } catch {
                showActionToast(message: error.localizedDescription, duration: 2.5)
            }
        }
    }

    private func defaultSnoozeDate() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
    private func dueDate(of reminder: EKReminder) -> Date? {
        reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
    }

    private func hasTime(of reminder: EKReminder) -> Bool {
        reminder.dueDateComponents?.hour != nil
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
                                                by: delta, count: rows.count), idx < rows.count else { return }
            selection = rows[idx]
            withAnimation { scrollProxy?.scrollTo(rowID(rows[idx]), anchor: .center) }
        case .scrollPage(let delta):
            let rows = navRows
            guard let first = rows.first, let last = rows.last else { return }
            withAnimation { scrollProxy?.scrollTo(rowID(delta < 0 ? first : last), anchor: delta < 0 ? .top : .bottom) }
        case .toggleHeader:
            showRecovery = true
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
                guard let reminder = (store.allReminders + store.completedReminders)
                    .first(where: { $0.calendarItemIdentifier == id }) else { return }
                performToggleCompletion(reminder)
            case .deleted(let uuid):
                guard let deleted = store.recentlyDeleted.first(where: { $0.id == uuid }) else { return }
                Task { @MainActor in
                    do {
                        try await store.restore(deleted)
                        undoEntry = nil
                        showActionToast(message: "Restored \"\(deleted.title)\"", duration: 2.5)
                    } catch {
                        showActionToast(message: error.localizedDescription, duration: 2.5)
                    }
                }
            case .tabHeader:
                showRecovery = true
            case nil:
                break
            }
        case .openRow:
            if case .reminder(let id) = selection,
               let reminder = (store.allReminders + store.completedReminders)
                    .first(where: { $0.calendarItemIdentifier == id }) {
                store.openInReminders(reminder)
            }
        case .deleteRow:
            switch selection {
            case .reminder(let id):
                guard let reminder = (store.allReminders + store.completedReminders)
                    .first(where: { $0.calendarItemIdentifier == id }) else { return }
                performDelete(reminder)
            case .deleted(let uuid):
                guard let deleted = store.recentlyDeleted.first(where: { $0.id == uuid }) else { return }
                pendingDeleteForever = deleted
                confirmDeleteForever = true
            case .tabHeader, nil:
                break
            }
        case .editRow:
            guard case .reminder(let id) = selection,
                  let reminder = (store.allReminders + store.completedReminders)
                    .first(where: { $0.calendarItemIdentifier == id }) else { return }
            editingReminder = reminder
        case .snoozeRow:
            guard case .reminder(let id) = selection,
                  let reminder = (store.allReminders + store.completedReminders)
                    .first(where: { $0.calendarItemIdentifier == id }),
                  !reminder.isCompleted else { return }
            beginSnooze(reminder)
        case .undo:
            performUndo()
        }
    }

    private func toggleHeader() {
        showRecovery = true
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

/// Measures the height of the collapsed composer block (editor + search row).
/// MainView reserves this space in the fixed list layer so the composer can
/// expand over the list instead of pushing it down.
private struct TopBlockHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
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
