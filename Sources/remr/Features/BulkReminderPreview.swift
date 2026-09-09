import CoreLocation
import EventKit
import SwiftUI

/// The lifecycle state of one row in the bulk creation preview.
enum BulkRowState: Equatable {
    case ready
    case created
    case failed(String)
}

/// A parsed reminder together with the selection and creation state shown by
/// ``BulkReminderPreview``. The UUID belongs to the preview row, not EventKit,
/// and therefore remains stable while a title is reparsed.
struct BulkReminderRow: Identifiable, Equatable {
    let id: UUID
    var draft: ReminderDraft
    var selected: Bool
    var state: BulkRowState
    var notice: String?
}

/// Pure state helpers used by the preview and by tests. Keeping row loading and
/// state transitions here makes it possible to exercise selection/retry logic
/// without constructing an EventKit store or performing a write.
struct BulkReminderPreviewState {
    var rows: [BulkReminderRow]

    init(rows: [BulkReminderRow] = []) {
        self.rows = rows
    }

    var hasCreatedRow: Bool {
        rows.contains { $0.state == .created }
    }

    var canCreateSelected: Bool {
        guard !rows.contains(where: { $0.selected && $0.state == .created }) else { return false }
        return rows.contains {
            $0.selected && !$0.draft.diagnostics.contains(.emptyTitle) && $0.state != .created
        }
    }

    var selectedCreatableIndices: [Int] {
        rows.indices.filter {
            let row = rows[$0]
            return row.selected && !row.draft.diagnostics.contains(.emptyTitle) && row.state != .created
        }
    }

    /// Builds rows from parser output. `resolveList` supplies only metadata;
    /// EventKit calendars are intentionally kept out of this pure helper.
    static func rows(from parsed: [ParsedReminder],
                     resolveList: (String) -> (identifier: String, title: String)?) -> [BulkReminderRow] {
        parsed.map { parsedReminder in
            let id = UUID()
            let metadata: (identifier: String, title: String)?
            if parsedReminder.listMatched, let token = parsedReminder.listToken {
                metadata = resolveList(token)
            } else {
                metadata = nil
            }
            let draft = ReminderDraft(
                id: id,
                rawInput: parsedReminder.original,
                title: parsedReminder.title,
                notes: "",
                dueDate: parsedReminder.dueDate,
                hasTime: parsedReminder.hasTime,
                priority: parsedReminder.priority,
                calendarIdentifier: metadata?.identifier,
                calendarTitle: metadata?.title,
                location: parsedReminder.locationPhrase.map(ReminderLocationDraft.unresolved) ?? .none,
                tags: parsedReminder.tags,
                diagnostics: parsedReminder.diagnostics
            )
            return BulkReminderRow(
                id: id,
                draft: draft,
                selected: !parsedReminder.isInvalid,
                state: .ready,
                notice: nil
            )
        }
    }

    /// Reparse one edited title, preserving that row's UUID and notes. The
    /// caller supplies list metadata so this method remains EventKit-free.
    mutating func reparseTitle(at index: Int,
                               title: String,
                               now: Date,
                               calendar: Calendar,
                               listNames: [String],
                               resolveList: (String) -> (identifier: String, title: String)?) {
        guard rows.indices.contains(index) else { return }
        var old = rows[index]
        let parsed = NaturalLanguageParser.parse(title, now: now, calendar: calendar, listNames: listNames)
        let metadata: (identifier: String, title: String)?
        if parsed.listMatched, let token = parsed.listToken {
            metadata = resolveList(token)
        } else {
            metadata = nil
        }
        old.draft = ReminderDraft(
            id: old.id,
            rawInput: title,
            title: parsed.title,
            notes: old.draft.notes,
            dueDate: parsed.dueDate,
            hasTime: parsed.hasTime,
            priority: parsed.priority,
            calendarIdentifier: metadata?.identifier,
            calendarTitle: metadata?.title,
            location: parsed.locationPhrase.map(ReminderLocationDraft.unresolved) ?? .none,
            tags: parsed.tags,
            diagnostics: parsed.diagnostics
        )
        old.state = .ready
        old.notice = nil
        if parsed.isInvalid {
            old.selected = false
        }
        rows[index] = old
    }

    mutating func markCreated(at index: Int) {
        guard rows.indices.contains(index) else { return }
        rows[index].state = .created
        rows[index].selected = false
    }

    mutating func markFailed(at index: Int, message: String) {
        guard rows.indices.contains(index) else { return }
        rows[index].state = .failed(message)
    }

    mutating func markReady(at index: Int, notice: String? = nil) {
        guard rows.indices.contains(index) else { return }
        rows[index].state = .ready
        rows[index].notice = notice
    }
}

/// A reusable, write-on-commit bulk reminder editor. Parsing and list lookup
/// happen while loading; geocoding and EventKit writes happen only from an
/// explicit Create/Retry action.
struct BulkReminderPreview: View {
    @EnvironmentObject private var store: ReminderStore

    let text: String
    let allowLocationLookup: Bool
    let onCancel: () -> Void
    let onDone: () -> Void

    @State private var rows: [BulkReminderRow] = []
    @State private var loadedText: String?
    @State private var listNames: [String] = []
    @State private var isProcessing = false
    @State private var loadError: String?
    @State private var bulkListIdentifier = ""

    init(text: String,
         allowLocationLookup: Bool = true,
         onCancel: @escaping () -> Void,
         onDone: @escaping () -> Void) {
        self.text = text
        self.allowLocationLookup = allowLocationLookup
        self.onCancel = onCancel
        self.onDone = onDone
        _rows = State(initialValue: [])
        _loadedText = State(initialValue: nil)
        _listNames = State(initialValue: [])
        _isProcessing = State(initialValue: false)
        _loadError = State(initialValue: nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Reminders")
                    .font(.headline)
                Spacer()
                Button("Cancel", action: onCancel)
                    .liquidGlassButtonStyle(.bordered)
                    .disabled(isProcessing)
                if hasCreatedRow {
                    Button("Done", action: onDone)
                        .liquidGlassButtonStyle(.bordered)
                        .keyboardShortcut(.defaultAction)
                }
                Button("Create Selected") {
                    createSelected()
                }
                .liquidGlassButtonStyle(.borderedProminent, prominent: true)
                .disabled(!canCreateSelected || isProcessing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if !rows.isEmpty {
                HStack {
                    Picker("List for selected", selection: $bulkListIdentifier) {
                        Text("Choose list").tag("")
                        ForEach(store.reminderCalendars(), id: \.calendarIdentifier) { calendar in
                            Text(calendar.title).tag(calendar.calendarIdentifier)
                        }
                    }
                    .frame(maxWidth: 220)
                    Button("Apply to Selected") {
                        applyBulkList()
                    }
                    .liquidGlassButtonStyle(.bordered)
                    .disabled(bulkListIdentifier.isEmpty || !rows.contains(where: { $0.selected && $0.state != .created }) || isProcessing)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }

            Divider()

            if isProcessing && rows.isEmpty {
                ProgressView("Interpreting reminders…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    Text(loadError)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        self.loadError = nil
                        loadedText = nil
                        loadRowsIfNeeded()
                    }
                    .liquidGlassButtonStyle(.borderedProminent, prominent: true)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No reminders")
                        .font(.headline)
                    Text("Enter one reminder per line.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach($rows) { $row in
                            BulkReminderRowEditor(row: $row,
                                                   listNames: listNames,
                                                   onRetry: { retry($row.wrappedValue.id) })
                                .environmentObject(store)
                                .disabled(isProcessing)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            loadRowsIfNeeded()
        }
        .onChange(of: text) { _ in
            loadRowsIfNeeded()
        }
    }

    private var hasCreatedRow: Bool {
        rows.contains { $0.state == .created }
    }

    private var canCreateSelected: Bool {
        guard !rows.contains(where: { $0.selected && $0.state == .created }) else { return false }
        return rows.contains {
            $0.selected && !$0.draft.diagnostics.contains(.emptyTitle) && $0.state != .created
        }
    }

    private func loadRowsIfNeeded() {
        guard loadedText != text else { return }
        loadedText = text
        let names = store.reminderCalendars().map(\.title)
        listNames = names
        loadError = nil
        isProcessing = true
        Task { @MainActor in
            do {
                let modelRows = try await OllamaReminderParser(model: SettingsStore.shared.ollamaModel).parseBulk(text)
                let now = Date()
                rows = modelRows.map { item, result in
                    let input = [result.title, result.deadlineText].compactMap { $0 }.joined(separator: " ")
                    var parsed = NaturalLanguageParser.parse(input, now: now, calendar: .current, listNames: names)
                    parsed.original = item.text
                    parsed.tags = item.tags
                    let resolved = parsed.listMatched
                        ? store.resolveList(token: parsed.listToken ?? "")
                        : (calendar: nil, matchedTitle: nil)
                    let parsedDraft = ReminderDraft.fromParsed(parsed,
                                                               notes: result.description,
                                                               calendar: resolved.calendar)
                    return BulkReminderRow(id: UUID(),
                                           draft: parsedDraft,
                                           selected: !parsed.isInvalid,
                                           state: .ready,
                                           notice: nil)
                }
                isProcessing = false
            } catch {
                rows = []
                loadError = error.localizedDescription
                loadedText = nil
                isProcessing = false
            }
        }
    }

    private func applyBulkList() {
        guard let calendar = store.reminderCalendars().first(where: { $0.calendarIdentifier == bulkListIdentifier }) else { return }
        for index in rows.indices where rows[index].selected && rows[index].state != .created {
            rows[index].draft.calendarIdentifier = calendar.calendarIdentifier
            rows[index].draft.calendarTitle = calendar.title
        }
    }

    private func createSelected() {
        guard !isProcessing else { return }
        let indices = rows.indices.filter {
            let row = rows[$0]
            return row.selected && !row.draft.diagnostics.contains(.emptyTitle) && row.state != .created
        }
        guard !indices.isEmpty else { return }
        isProcessing = true
        Task { @MainActor in
            for index in indices {
                await createRow(at: index)
            }
            isProcessing = false
        }
    }

    private func retry(_ id: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == id }),
              !isProcessing,
              case .failed = rows[index].state else { return }
        isProcessing = true
        Task { @MainActor in
            await createRow(at: index)
            isProcessing = false
        }
    }

    private func createRow(at index: Int) async {
        guard rows.indices.contains(index) else { return }
        var draft = rows[index].draft
        if case .unresolved(let phrase) = draft.location {
            if allowLocationLookup {
                if let located = await LocationGeocoder.shared.geocode(phrase) {
                    draft.location = .resolved(DeletedLocation(title: located.title,
                                                                latitude: located.latitude,
                                                                longitude: located.longitude,
                                                                radius: 100))
                } else {
                    draft.title += " at \(phrase)"
                    draft.location = .none
                    rows[index].notice = "Couldn't find location “\(phrase)” — added it to the title"
                }
            } else {
                // Voice flows are strictly offline. Preserve the spoken place
                // without invoking CLGeocoder or failing EventKit creation.
                draft.title += " at \(phrase)"
                draft.location = .none
                rows[index].notice = "Location lookup is disabled for voice entries — added it to the title"
            }
            rows[index].draft = draft
        }

        do {
            _ = try await store.create(from: draft)
            rows[index].selected = false
            rows[index].state = .created
        } catch {
            rows[index].draft = draft
            rows[index].state = .failed(error.localizedDescription)
        }
    }

    private struct BulkReminderRowEditor: View {
        @EnvironmentObject private var store: ReminderStore
        @Binding var row: BulkReminderRow
        let listNames: [String]

        private var isEmptyTitle: Bool {
            row.draft.diagnostics.contains(.emptyTitle)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Toggle("", isOn: Binding(get: {
                        row.selected
                    }, set: { selected in
                        guard !isEmptyTitle else { return }
                        row.selected = selected
                    }))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .disabled(isEmptyTitle || row.state == .created)

                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Title", text: titleBinding)
                            .textFieldStyle(.roundedBorder)
                        TextField("Notes", text: notesBinding, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...4)
                        draftChips
                        if let notice = row.notice {
                            Text(notice)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        diagnostics
                    }

                    Spacer(minLength: 0)
                    stateView
                }
                structuredFields
            }
            .padding(10)
            .liquidGlassField(in: RoundedRectangle(cornerRadius: 8))
        }

        private var titleBinding: Binding<String> {
            Binding(get: { row.draft.title }, set: reparseTitle(_:))
        }

        private func reparseTitle(_ title: String) {
            let old = row.draft
            let parsed = NaturalLanguageParser.parse(title,
                                                     now: Date(),
                                                     calendar: .current,
                                                     listNames: listNames)
            let resolved: (calendar: EKCalendar?, matchedTitle: String?)
            if parsed.listMatched {
                resolved = store.resolveList(token: parsed.listToken ?? "")
            } else {
                resolved = (nil, nil)
            }
            let parsedDraft = ReminderDraft.fromParsed(parsed, notes: old.notes, calendar: resolved.calendar)
            row.draft = ReminderDraft(id: row.id,
                                      rawInput: parsedDraft.rawInput,
                                      title: parsedDraft.title,
                                      notes: parsedDraft.notes,
                                      dueDate: parsedDraft.dueDate,
                                      hasTime: parsedDraft.hasTime,
                                      priority: parsedDraft.priority,
                                      calendarIdentifier: parsedDraft.calendarIdentifier,
                                      calendarTitle: parsedDraft.calendarTitle,
                                      location: parsedDraft.location,
                                      tags: parsedDraft.tags,
                                      diagnostics: parsedDraft.diagnostics)
            row.state = .ready
            row.notice = nil
            if parsed.isInvalid {
                row.selected = false
            }
        }

        private var notesBinding: Binding<String> {
            Binding(get: { row.draft.notes }, set: { row.draft.notes = $0 })
        }

        @ViewBuilder
        private var draftChips: some View {
            HStack(spacing: 5) {
                if let due = row.draft.dueDate {
                    chip(ReminderRowView.dateLabel(for: due))
                    if row.draft.hasTime {
                        chip(due.formatted(date: .omitted, time: .shortened))
                    }
                }
                if let calendarTitle = row.draft.calendarTitle, !calendarTitle.isEmpty {
                    chip("@\(calendarTitle)")
                }
                if row.draft.priority != 0 {
                    chip(priorityLabel)
                }
                if case .unresolved(let phrase) = row.draft.location, !phrase.isEmpty {
                    chip("at \(phrase)")
                } else if case .resolved(let location) = row.draft.location, !location.title.isEmpty {
                    chip("at \(location.title)")
                }
                ForEach(row.draft.tags, id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .liquidGlassChip(tint: TagStore.shared.color(for: tag))
                }
            }
            .foregroundStyle(.secondary)
        }

        private var priorityLabel: String {
            switch row.draft.priority {
            case 1: return "High priority"
            case 5: return "Medium priority"
            case 9: return "Low priority"
            default: return "Priority"
            }
        }

        private func chip(_ text: String) -> some View {
            Text(text)
                .font(.caption2)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .liquidGlassChip()
        }

        @ViewBuilder
        private var diagnostics: some View {
            ForEach(Array(row.draft.diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                Text(message(for: diagnostic))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }

        private func message(for diagnostic: ParserDiagnostic) -> String {
            switch diagnostic {
            case .emptyTitle:
                return "Add a title"
            case .unmatchedList(let token):
                return "List “@\(token)” was not found"
            }
        }

        @ViewBuilder
        private var stateView: some View {
            VStack(alignment: .trailing, spacing: 5) {
                switch row.state {
                case .ready:
                    Text("Ready")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .created:
                    Label("Created", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                case .failed(let message):
                    Text(message)
                        .font(.caption)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.red)
                    Button("Retry", action: onRetry)
                        .liquidGlassButtonStyle(.bordered)
                }
            }
        }

        let onRetry: () -> Void

        @ViewBuilder
        private var structuredFields: some View {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Toggle("Due date", isOn: dueEnabledBinding)
                    if row.draft.dueDate != nil {
                        Toggle("All day", isOn: allDayBinding)
                    }
                }
                if row.draft.dueDate != nil {
                    DatePicker("Date", selection: dueDateBinding)
                        .datePickerStyle(.field)
                }
                HStack {
                    Picker("List", selection: listBinding) {
                        Text("Default list").tag("")
                        ForEach(store.reminderCalendars(), id: \.calendarIdentifier) { calendar in
                            Text(calendar.title).tag(calendar.calendarIdentifier)
                        }
                    }
                    Picker("Priority", selection: priorityBinding) {
                        Text("None").tag(0)
                        Text("High").tag(1)
                        Text("Medium").tag(5)
                        Text("Low").tag(9)
                    }
                }
                TextField("Location phrase", text: locationBinding)
                    .textFieldStyle(.roundedBorder)
                TextField("Tags (#tag #another)", text: tagsBinding)
                    .textFieldStyle(.roundedBorder)
            }
            .font(.caption)
        }

        private var dueEnabledBinding: Binding<Bool> {
            Binding(get: { row.draft.dueDate != nil }, set: { enabled in
                if enabled {
                    row.draft.dueDate = row.draft.dueDate ?? Self.defaultDueDate()
                } else {
                    row.draft.dueDate = nil
                    row.draft.hasTime = false
                }
            })
        }

        private var allDayBinding: Binding<Bool> {
            Binding(get: { !row.draft.hasTime }, set: { allDay in
                row.draft.hasTime = !allDay
                if allDay, let date = row.draft.dueDate {
                    row.draft.dueDate = Calendar.current.startOfDay(for: date)
                }
            })
        }

        private var dueDateBinding: Binding<Date> {
            Binding(get: { row.draft.dueDate ?? Self.defaultDueDate() }, set: { row.draft.dueDate = $0 })
        }

        private var listBinding: Binding<String> {
            Binding(get: { row.draft.calendarIdentifier ?? "" }, set: { identifier in
                guard !identifier.isEmpty,
                      let calendar = store.reminderCalendars().first(where: { $0.calendarIdentifier == identifier }) else {
                    row.draft.calendarIdentifier = nil
                    row.draft.calendarTitle = nil
                    return
                }
                row.draft.calendarIdentifier = calendar.calendarIdentifier
                row.draft.calendarTitle = calendar.title
            })
        }

        private var priorityBinding: Binding<Int> {
            Binding(get: { row.draft.priority }, set: { row.draft.priority = $0 })
        }

        private var locationBinding: Binding<String> {
            Binding(get: {
                switch row.draft.location {
                case .none: return ""
                case .unresolved(let phrase): return phrase
                case .resolved(let location): return location.title
                }
            }, set: { phrase in
                let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
                row.draft.location = trimmed.isEmpty ? .none : .unresolved(trimmed)
            })
        }

        private var tagsBinding: Binding<String> {
            Binding(get: { row.draft.tags.map { "#\($0)" }.joined(separator: " ") }, set: {
                row.draft.tags = NaturalLanguageParser.extractTags(from: $0)
            })
        }

        private static func defaultDueDate() -> Date {
            let calendar = Calendar.current
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            var components = calendar.dateComponents([.year, .month, .day], from: tomorrow)
            components.hour = 9
            components.minute = 0
            return calendar.date(from: components) ?? tomorrow
        }
    }
}
