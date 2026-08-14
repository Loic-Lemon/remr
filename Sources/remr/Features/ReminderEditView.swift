import CoreLocation
import EventKit
import SwiftUI

/// Inline editor for an existing reminder. The draft is a snapshot of the
/// EventKit item and is never reparsed, so dates and priorities retain their
/// stored values when a reminder is opened.
struct ReminderEditView: View {
    @EnvironmentObject private var store: ReminderStore

    let reminder: EKReminder
    let onCancel: () -> Void
    let onSaved: (String) -> Void

    @State private var draft: ReminderDraft
    @State private var locationText: String
    @State private var tagsText: String
    /// The state captured at open; Cancel with unsaved changes asks first.
    @State private var initialDraft: ReminderDraft
    @State private var initialLocationText: String
    @State private var initialTagsText: String
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var confirmDiscard = false
    @State private var titleFocusRequest = 0
    @State private var notesFocusRequest = 0
    @FocusState private var focusedField: Field?
    @ObservedObject private var tagStore = TagStore.shared

    private enum Field: Hashable {
        case title
        case notes
    }

    init(reminder: EKReminder,
         onCancel: @escaping () -> Void,
         onSaved: @escaping (String) -> Void) {
        self.reminder = reminder
        self.onCancel = onCancel
        self.onSaved = onSaved
        let initial = ReminderDraft.fromReminder(reminder)
        _draft = State(initialValue: initial)
        _initialDraft = State(initialValue: initial)
        let locationPhrase = Self.locationPhrase(from: initial.location)
        _locationText = State(initialValue: locationPhrase)
        _initialLocationText = State(initialValue: locationPhrase)
        let tagsText = initial.tags.map { "#\($0)" }.joined(separator: " ")
        _tagsText = State(initialValue: tagsText)
        _initialTagsText = State(initialValue: tagsText)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .zIndex(1)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    fieldLabel("Title")
                    titleField
                    fieldLabel("Description")
                    notesField
                    scheduleSection
                    detailsSection
                }
            }
            .clipped()
            if let errorMessage {
                errorBanner(errorMessage)
            }
            Divider()
                .padding(.horizontal, 12)
                .padding(.top, 8)
            footer
        }
        .liquidGlassPane(in: EntryContainerShape())
        .onAppear { focusedField = .title }
        .confirmationDialog("Discard changes?", isPresented: $confirmDiscard,
                            titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) {
                onCancel()
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Your edits to this reminder have not been saved.")
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Edit Reminder")
                .font(.title3.weight(.semibold))
            Spacer()
            if let calendar = reminder.calendar {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color(calendar.color))
                        .frame(width: 8, height: 8)
                    Text(calendar.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .liquidGlassChip()
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var titleField: some View {
        ReminderInputView(text: $draft.title,
                          onMoveDown: {
                              focusedField = .notes
                              notesFocusRequest += 1
                          },
                          focusRequest: titleFocusRequest,
                          onFocusForward: {
                              focusedField = .notes
                              notesFocusRequest += 1
                          })
        .focused($focusedField, equals: .title)
        .frame(height: 34)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .liquidGlassField(in: RoundedRectangle(cornerRadius: 9))
        .padding(.horizontal, 12)
    }

    private var notesField: some View {
        ReminderInputView(text: $draft.notes,
                          onSubmit: save,
                          focusRequest: notesFocusRequest,
                          onFocusBack: {
                              focusedField = .title
                              titleFocusRequest += 1
                          })
        .focused($focusedField, equals: .notes)
        .frame(minHeight: 34, maxHeight: 110)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .liquidGlassField(in: RoundedRectangle(cornerRadius: 9))
        .padding(.horizontal, 12)
    }


    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Day")
            HStack {
                Text("Due date")
                    .font(.callout)
                Spacer()
                Toggle("", isOn: dueDateEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }
            .padding(.vertical, 8)
            if draft.dueDate != nil {
                // Quick upcoming days: Today, Tomorrow, then weekday + day
                // number. Each sets the day and keeps the current time.
                VStack(alignment: .leading, spacing: 5) {
                    Text("QUICK")
                        .font(.caption2.weight(.semibold))
                        .kerning(0.8)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 5) {
                        ForEach(quickDays, id: \.id) { day in
                            Button {
                                applyQuickDay(day.id)
                            } label: {
                                Text(day.label)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .liquidGlassChip()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 8)

                // Compact calendar — always visible, tap a day directly.
                MonthCalendar(selected: dueDateBinding)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(AppPalette.controlStroke, lineWidth: 1))
                    .padding(.vertical, 8)

                sectionHeader("Time")
                if draft.hasTime {
                    HStack(spacing: 5) {
                        ForEach(TimePreset.allCases, id: \.self) { preset in
                            let isActive = timePresetIsActive(preset)
                            Button {
                                applyTimePreset(preset)
                            } label: {
                                Text(preset.label)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(isActive ? Color.white : Color.primary)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .liquidGlassChip(tint: isActive ? Color.accentColor : nil,
                                                     filled: isActive)
                            }
                            .buttonStyle(.plain)
                            .help(preset.help)
                        }
                    }
                    .padding(.vertical, 4)
                }
                timeSteppers
                    .disabled(!draft.hasTime)
                    .padding(.vertical, 4)
                HStack {
                    Text("All-day")
                        .font(.callout)
                    Spacer()
                    Toggle("", isOn: allDayBinding)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                }
                .padding(.vertical, 8)
            }
        }
        .padding(.horizontal, 12)
    }

    /// Direct time editing: hour and minute steppers plus an AM/PM toggle —
    /// alarm-clock style. No typing, no buried popover, wraps like a clock.
    /// 12-hour with AM/PM where the locale uses it, 24-hour otherwise.
    private var timeSteppers: some View {
        HStack(spacing: 6) {
            miniStepper(value: hourLabel,
                        up: { setHour(hourValue + 1) },
                        down: { setHour(hourValue - 1) })
            Text(":")
                .font(.callout)
                .foregroundStyle(.secondary)
            miniStepper(value: minuteLabel,
                        up: { setMinute(minuteValue + 5) },
                        down: { setMinute(minuteValue - 5) })
            if Self.usesAMPM {
                Picker("", selection: isAMPicker) {
                    Text("AM").tag(true)
                    Text("PM").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 80)
                .controlSize(.small)
            }
        }
    }

    private func miniStepper(value: String,
                             up: @escaping () -> Void,
                             down: @escaping () -> Void) -> some View {
        HStack(spacing: 5) {
            VStack(spacing: 1) {
                Button(action: up) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 8, weight: .semibold))
                        .frame(width: 16, height: 12)
                }
                .buttonStyle(.plain)
                Button(action: down) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .frame(width: 16, height: 12)
                }
                .buttonStyle(.plain)
            }
            Text(value)
                .font(.callout.monospacedDigit())
                .frame(minWidth: 26)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .liquidGlassField(in: RoundedRectangle(cornerRadius: 7))
    }

    /// Whether the current locale formats times with an AM/PM marker.
    private static let usesAMPM: Bool = {
        guard let format = DateFormatter.dateFormat(fromTemplate: "j",
                                                    options: 0,
                                                    locale: .current) else { return false }
        return format.contains("a")
    }()

    private var hourValue: Int {
        guard let due = draft.dueDate else { return 0 }
        let hour = Calendar.current.component(.hour, from: due)
        if Self.usesAMPM {
            let h = hour % 12
            return h == 0 ? 12 : h
        }
        return hour
    }

    private var minuteValue: Int {
        guard let due = draft.dueDate else { return 0 }
        return Calendar.current.component(.minute, from: due)
    }

    private var hourLabel: String {
        Self.usesAMPM ? "\(hourValue)" : String(format: "%02d", hourValue)
    }

    private var minuteLabel: String {
        String(format: "%02d", minuteValue)
    }

    private var isAM: Bool {
        guard let due = draft.dueDate else { return true }
        return Calendar.current.component(.hour, from: due) < 12
    }

    private var isAMPicker: Binding<Bool> {
        Binding(
            get: { isAM },
            set: { am in
                guard let due = draft.dueDate else { return }
                let calendar = Calendar.current
                let h12 = calendar.component(.hour, from: due) % 12
                draft.dueDate = calendar.date(bySettingHour: (am ? 0 : 12) + h12,
                                              minute: calendar.component(.minute, from: due),
                                              second: 0,
                                              of: due)
                draft.hasTime = true
            }
        )
    }

    private func setHour(_ h: Int) {
        guard let due = draft.dueDate else { return }
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: due)
        let h24: Int
        if Self.usesAMPM {
            var h12 = h
            if h12 > 12 { h12 = 1 } else if h12 < 1 { h12 = 12 }
            h24 = (h12 % 12) + (isAM ? 0 : 12)
        } else {
            h24 = ((h % 24) + 24) % 24
        }
        draft.dueDate = calendar.date(bySettingHour: h24, minute: minute, second: 0, of: due)
        draft.hasTime = true
    }

    private func setMinute(_ m: Int) {
        guard let due = draft.dueDate else { return }
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: due)
        let minute = ((m % 60) + 60) % 60
        draft.dueDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: due)
        draft.hasTime = true
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Details")
            HStack {
                Text("Priority")
                    .font(.callout)
                Spacer()
                Picker("", selection: priorityBinding) {
                    Text("None").tag(0)
                    Text("!").tag(1)
                    Text("!!").tag(5)
                    Text("!!!").tag(9)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 176)
            }
            .padding(.vertical, 8)
            HStack {
                Text("List")
                    .font(.callout)
                Spacer()
                Picker("", selection: calendarBinding) {
                    Text("Default list").tag("")
                    ForEach(calendarChoices, id: \.calendarIdentifier) { calendar in
                        Text(calendar.title).tag(calendar.calendarIdentifier)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()
            }
            .padding(.vertical, 8)

            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                TextField("Location", text: $locationText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .liquidGlassField()
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "number")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    TextField("#home #errands", text: $tagsText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .liquidGlassField()
                tagChipsPreview
            }
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 12)
    }

    /// Live preview of the tags parsed from the tags field — chips
    /// materialize as you type, matching the composer's parse preview.
    @ViewBuilder
    private var tagChipsPreview: some View {
        let tags = NaturalLanguageParser.extractTags(from: tagsText)
        if !tags.isEmpty {
            HStack(spacing: 4) {
                ForEach(tags, id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .liquidGlassChip(tint: tagStore.color(for: tag), filled: true)
                }
            }
            .padding(.leading, 2)
        }
    }

    /// A small label for a text field (Title, Description), matching the
    /// section-header style but without the divider.
    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 5)
    }

    private func sectionHeader(_ title: String) -> some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.top, 14)
                .padding(.bottom, 10)
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var footer: some View {
        HStack {
            Button("Cancel", action: requestCancel)
                .liquidGlassButtonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button(action: save) {
                HStack(spacing: 6) {
                    if saving {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(saving ? "Saving…" : "Save")
                }
            }
            .liquidGlassButtonStyle(.borderedProminent, prominent: true)
            .keyboardShortcut(.defaultAction)
            .disabled(saving || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
    }

    /// Cancel with unsaved changes asks before discarding.
    private func requestCancel() {
        if isDirty && !saving {
            confirmDiscard = true
        } else {
            onCancel()
        }
    }

    private var isDirty: Bool {
        draft != initialDraft
            || locationText != initialLocationText
            || tagsText != initialTagsText
    }

    /// The next few days as tappable quick options: Today, Tomorrow, then
    /// weekday + day number. Each sets the day and keeps the current
    /// time-of-day (or stays all-day).
    private struct QuickDay {
        let id: Date
        let label: String
    }

    private var quickDays: [QuickDay] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        return (0..<6).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: start) ?? start
            let label: String
            if offset == 0 {
                label = "Today"
            } else if offset == 1 {
                label = "Tomorrow"
            } else {
                label = day.formatted(.dateTime.weekday(.abbreviated))
                    + " " + String(calendar.component(.day, from: day))
            }
            return QuickDay(id: day, label: label)
        }
    }

    private func applyQuickDay(_ day: Date) {
        if draft.hasTime {
            let calendar = Calendar.current
            let time = calendar.dateComponents([.hour, .minute], from: draft.dueDate ?? Date())
            draft.dueDate = calendar.date(bySettingHour: time.hour ?? 9,
                                          minute: time.minute ?? 0,
                                          second: 0,
                                          of: day)
        } else {
            draft.dueDate = day
        }
    }

    /// Quick times covering the day; each sets the hour on the picked date.
    private enum TimePreset: String, CaseIterable {
        case early = "7 AM"
        case morning = "9 AM"
        case noon = "Noon"
        case afternoon = "3 PM"
        case evening = "5 PM"
        case night = "8 PM"

        var label: String { rawValue }

        var help: String { "Set time to \(rawValue)" }

        var hour: Int {
            switch self {
            case .early: return 7
            case .morning: return 9
            case .noon: return 12
            case .afternoon: return 15
            case .evening: return 17
            case .night: return 20
            }
        }
    }

    private func applyTimePreset(_ preset: TimePreset) {
        let day = draft.dueDate ?? Date()
        draft.dueDate = Calendar.current.date(bySettingHour: preset.hour,
                                              minute: 0,
                                              second: 0,
                                              of: day)
        draft.hasTime = true
    }

    /// True when the reminder's due time is exactly this preset (hour on
    /// the dot), so the matching quick chip is highlighted as active.
    private func timePresetIsActive(_ preset: TimePreset) -> Bool {
        guard draft.hasTime, let due = draft.dueDate else { return false }
        let calendar = Calendar.current
        return calendar.component(.hour, from: due) == preset.hour
            && calendar.component(.minute, from: due) == 0
    }

    private var calendarChoices: [EKCalendar] {
        var calendars = store.reminderCalendars()
        if let current = reminder.calendar,
           !calendars.contains(where: { $0.calendarIdentifier == current.calendarIdentifier }) {
            calendars.insert(current, at: 0)
        }
        return calendars
    }

    private var dueDateEnabled: Binding<Bool> {
        Binding(
            get: { draft.dueDate != nil },
            set: { enabled in
                if enabled {
                    draft.dueDate = draft.dueDate ?? Self.defaultDueDate()
                    draft.hasTime = true
                } else {
                    draft.dueDate = nil
                }
            }
        )
    }

    /// Non-optional due-date binding for the calendar; the panel only exists
    /// while a due date is set, so the fallback is never user-visible.
    private var dueDateBinding: Binding<Date> {
        Binding(
            get: { draft.dueDate ?? Self.defaultDueDate() },
            set: { draft.dueDate = $0 }
        )
    }

    /// All-day is the inverse of `hasTime`. Turning it on snaps the due date
    /// to midnight; turning it off on an all-day date defaults the time to
    /// 9:00 AM instead of leaving it at midnight.
    private var allDayBinding: Binding<Bool> {
        Binding(
            get: { !draft.hasTime },
            set: { allDay in
                if allDay {
                    draft.hasTime = false
                    if let due = draft.dueDate {
                        draft.dueDate = Calendar.current.startOfDay(for: due)
                    }
                } else {
                    draft.hasTime = true
                    if let due = draft.dueDate,
                       due == Calendar.current.startOfDay(for: due),
                       let timed = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: due) {
                        draft.dueDate = timed
                    }
                }
            }
        )
    }

    private var calendarBinding: Binding<String> {
        Binding(
            get: { draft.calendarIdentifier ?? "" },
            set: { identifier in
                guard !identifier.isEmpty else {
                    draft.calendarIdentifier = nil
                    draft.calendarTitle = nil
                    return
                }
                let calendar = store.reminderCalendars().first { $0.calendarIdentifier == identifier }
                draft.calendarIdentifier = identifier
                draft.calendarTitle = calendar?.title
            }
        )
    }

    private var priorityBinding: Binding<Int> {
        Binding(get: { draft.priority }, set: { draft.priority = $0 })
    }

    private func save() {
        guard !saving else { return }
        saving = true
        errorMessage = nil

        var candidate = draft
        candidate.tags = NaturalLanguageParser.extractTags(from: tagsText)
        let phrase = locationText.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalPhrase = Self.locationPhrase(from: draft.location)
        if phrase.isEmpty {
            candidate.location = .none
        } else if phrase == originalPhrase, case .resolved = draft.location {
            // Preserve the existing structured location when its phrase was not edited.
            candidate.location = draft.location
        } else {
            candidate.location = .unresolved(phrase)
        }

        let initialCandidate = candidate
        Task { @MainActor [initialCandidate] in
            var candidate = initialCandidate
            if case .unresolved(let phrase) = candidate.location {
                guard let located = await LocationGeocoder.shared.geocode(phrase) else {
                    saving = false
                    errorMessage = "Couldn't find location “\(phrase)” — choose another location or clear it"
                    return
                }
                candidate.location = .resolved(DeletedLocation(title: located.title,
                                                                 latitude: located.latitude,
                                                                 longitude: located.longitude,
                                                                 radius: 100))
            }

            do {
                try await store.update(reminder, from: candidate)
                draft = candidate
                saving = false
                onSaved(reminder.calendarItemIdentifier)
            } catch {
                saving = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private static func locationPhrase(from location: ReminderLocationDraft) -> String {
        if case .resolved(let value) = location { return value.title }
        if case .unresolved(let value) = location { return value }
        return ""
    }

    private static func defaultDueDate() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    private struct EntryContainerShape: Shape {
        func path(in rect: CGRect) -> Path {
            let radius = min(9, min(rect.width, rect.height) / 2)
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY),
                              control: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                              control: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }
}

/// A compact, hand-built month calendar — pure SwiftUI, no NSDatePicker (the
/// native control crashed AppKit's layout pass inside this popover). Tap a
/// day to pick; the current selection's time-of-day is preserved.
private struct MonthCalendar: View {
    let calendar = Calendar.current
    @Binding var selected: Date
    @State private var month: Date
    @State private var hoveredDay: Int?

    init(selected: Binding<Date>) {
        _selected = selected
        _month = State(initialValue: Calendar.current.dateInterval(of: .month, for: selected.wrappedValue)?.start
                       ?? selected.wrappedValue)
    }

    /// Weekday headers rotated to the calendar's first weekday.
    private var weekdaySymbols: [String] {
        CalendarGridMath.weekdaySymbols(calendar: calendar)
    }

    /// Empty leading cells so the 1st lands in its weekday column.
    private var leadingBlanks: Int {
        CalendarGridMath.leadingBlanks(for: month, calendar: calendar)
    }

    private var daysInMonth: Int {
        CalendarGridMath.daysInMonth(for: month, calendar: calendar)
    }

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Button {
                    if let m = calendar.date(byAdding: .month, value: -1, to: month) { month = m }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 18)
                }
                .buttonStyle(.plain)
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.callout.weight(.semibold))
                Spacer()
                Button {
                    if let m = calendar.date(byAdding: .month, value: 1, to: month) { month = m }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 18)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            HStack(spacing: 4) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                      spacing: 4) {
                ForEach(0..<(leadingBlanks + daysInMonth), id: \.self) { index in
                    if index < leadingBlanks {
                        Color.clear
                            .frame(height: 24)
                    } else {
                        dayCell(index - leadingBlanks + 1)
                    }
                }
            }
        }
        .onChange(of: selected) { newDate in
            // Follow external selection changes (e.g. a quick chip) to its month.
            if let start = calendar.dateInterval(of: .month, for: newDate)?.start {
                month = start
            }
        }
    }

    private func dayCell(_ day: Int) -> some View {
        let date = calendar.date(byAdding: .day, value: day - 1, to: month)!
        let isSelected = calendar.isDate(date, inSameDayAs: selected)
        let isToday = calendar.isDateInToday(date)
        let isHovered = hoveredDay == day
        return Button {
            // Move the date, keep the selected time-of-day.
            var components = calendar.dateComponents([.year, .month, .day], from: date)
            let time = calendar.dateComponents([.hour, .minute], from: selected)
            components.hour = time.hour
            components.minute = time.minute
            if let d = calendar.date(from: components) {
                selected = d
            }
        } label: {
            Text("\(day)")
                .font(.caption)
                .frame(maxWidth: .infinity, minHeight: 24)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.accentColor)
                    } else if isToday {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.1))
                    }
                }
                .foregroundStyle(isSelected ? Color.white : (isToday ? Color.accentColor : Color.primary))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredDay = hovering ? day : nil
        }
    }
}
