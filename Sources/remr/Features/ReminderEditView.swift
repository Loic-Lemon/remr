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
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var titleFocusRequest = 0
    @State private var notesFocusRequest = 0
    @FocusState private var focusedField: Field?

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
        _locationText = State(initialValue: Self.locationPhrase(from: initial.location))
        _tagsText = State(initialValue: initial.tags.map { "#\($0)" }.joined(separator: " "))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                titleField
                notesField
                controls
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                }
                HStack {
                    Button("Cancel", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button(saving ? "Saving…" : "Save", action: save)
                        .keyboardShortcut(.defaultAction)
                        .disabled(saving || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(12)
            }
        }
        .liquidGlassField(in: EntryContainerShape())
        .onAppear { focusedField = .title }
    }

    private var titleField: some View {
        ZStack(alignment: .topLeading) {
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
            if draft.title.isEmpty {
                Text("Reminder title")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
        }
        .focused($focusedField, equals: .title)
        .frame(height: 34)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var notesField: some View {
        ZStack(alignment: .topLeading) {
            ReminderInputView(text: $draft.notes,
                              onSubmit: save,
                              focusRequest: notesFocusRequest,
                              onFocusBack: {
                                  focusedField = .title
                                  titleFocusRequest += 1
                              })
            if draft.notes.isEmpty {
                Text("Add description…")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
        }
        .focused($focusedField, equals: .notes)
        .frame(minHeight: 34, maxHeight: 110)
        .padding(.horizontal, 12)
        .padding(.top, 2)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Due date", isOn: dueDateEnabled)
            if draft.dueDate != nil {
                DatePicker("Date", selection: dueDateBinding,
                           displayedComponents: draft.hasTime ? [.date, .hourAndMinute] : [.date])
                Toggle("Time", isOn: hasTimeBinding)
            }

            Picker("List", selection: calendarBinding) {
                Text("Default list").tag("")
                ForEach(calendarChoices, id: \.calendarIdentifier) { calendar in
                    Text(calendar.title).tag(calendar.calendarIdentifier)
                }
            }

            Picker("Priority", selection: priorityBinding) {
                Text("None").tag(0)
                Text("High").tag(1)
                Text("Medium").tag(5)
                Text("Low").tag(9)
            }

            TextField("Location", text: $locationText)
                .textFieldStyle(.roundedBorder)
            TextField("Tags (e.g. #home #errands)", text: $tagsText)
                .textFieldStyle(.roundedBorder)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
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

    private var dueDateBinding: Binding<Date> {
        Binding(
            get: { draft.dueDate ?? Self.defaultDueDate() },
            set: { draft.dueDate = $0 }
        )
    }

    private var hasTimeBinding: Binding<Bool> {
        Binding(
            get: { draft.hasTime },
            set: { draft.hasTime = $0 }
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
                guard let coordinate = await LocationGeocoder.shared.geocode(phrase) else {
                    saving = false
                    errorMessage = "Couldn't find location “\(phrase)” — choose another location or clear it"
                    return
                }
                candidate.location = .resolved(DeletedLocation(title: phrase,
                                                                 latitude: coordinate.coordinate.latitude,
                                                                 longitude: coordinate.coordinate.longitude,
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
