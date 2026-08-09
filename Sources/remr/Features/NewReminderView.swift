import CoreLocation
import EventKit
import SwiftUI

/// Single-reminder editor: the title parses due date / list / priority /
/// location tokens; a description line appears as you type. Enter in the
/// title moves to the description; Enter in the description creates the
/// reminder; Shift+Enter inserts a newline in the description.
struct NewReminderView: View {
    @EnvironmentObject var store: ReminderStore
    @State private var title: String
    @State private var notes = ""
    @State private var saving = false
    @State private var saveError: String?
    /// Bumped to move focus from the title into the description.
    @State private var notesFocusRequest = 0
    /// Explicit SwiftUI focus identity — without it, macOS 26's focus system
    /// hands focus to the description the moment it appears.
    @FocusState private var focusedField: EntryField?
    /// Keyword-suggestion dropdown: token at the title's caret, selection,
    /// and whether the title field actually has focus.
    @State private var completionToken = ""
    @State private var selectedSuggestion = 0
    @State private var titleFocused = false
    @State private var replaceTokenRequest = 0
    @State private var replaceTokenWith = ""

    init(prefillText: String = "") {
        // Service / global-input prefill: first line is the title, the
        // remaining lines become the description.
        let lines = prefillText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let initialTitle = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let initialNotes = lines.dropFirst()
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        _title = State(initialValue: initialTitle)
        _notes = State(initialValue: initialNotes)
    }

    var body: some View {
        VStack(spacing: 0) {
            titleField
            if titleFocused, !suggestionMatches.isEmpty {
                suggestionDropdown
            }
            if !title.isEmpty || !notes.isEmpty {
                notesField
            }
            if let saveError {
                Text(saveError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }
            // The add area is part of the pane: no box, just this single
            // full-width hairline separating it from the search row below.
            Divider()
        }
        .preferredColorScheme(.light)
    }

    private var titleField: some View {
        ZStack(alignment: .topLeading) {
            ReminderInputView(
                text: $title, refocusOnClear: true, onMoveDown: titleReturnPressed,
                onTokenChange: { completionToken = $0; selectedSuggestion = 0 },
                onFocusChange: { titleFocused = $0 },
                dropdownActive: titleFocused && !suggestionMatches.isEmpty,
                onNavigate: navigateSuggestion,
                onDismiss: { completionToken = "" },
                replaceTokenRequest: replaceTokenRequest,
                replaceTokenWith: replaceTokenWith
            )
            if title.isEmpty {
                Text("e.g. Take out the trash before end of day @home")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
        }
        .focused($focusedField, equals: .title)
        .frame(height: 32)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    /// Keyword suggestions matching the title's current token (only fires for
    /// letters that could start a keyword; never for `@`/`#` tokens).
    private var suggestionMatches: [String] {
        let token = completionToken.lowercased()
        guard token.count >= 2, !token.hasPrefix("@"), !token.hasPrefix("#") else { return [] }
        return Self.keywords.filter { $0.hasPrefix(token) && $0 != token }
    }

    private var suggestionDropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestionMatches.enumerated()), id: \.offset) { index, keyword in
                Button {
                    acceptSuggestion(keyword)
                } label: {
                    Text(keyword)
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(index == selectedSuggestion ? Color.accentColor.opacity(0.16) : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(RoundedRectangle(cornerRadius: 7).fill(AppPalette.fieldFill))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(AppPalette.fieldStroke, lineWidth: 1))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private var notesField: some View {
        ZStack(alignment: .topLeading) {
            ReminderInputView(text: $notes, onSubmit: submit, focusRequest: notesFocusRequest,
                              onAppearInWindow: { focusedField = .title })
            if notes.isEmpty {
                Text("Add description…")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
        }
        .focused($focusedField, equals: .notes)
        .frame(height: notesFieldHeight)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private enum EntryField: Hashable {
        case title
        case notes
    }

    /// Grows with the description (one line ≈ 32pt, capped at ~5 lines) so a
    /// fresh box is compact instead of a tall empty slab.
    private var notesFieldHeight: CGFloat {
        let lines = max(1, notes.split(whereSeparator: { $0.isNewline }).count)
        return min(16 + CGFloat(lines) * 16, 96)
    }

    /// Keyword completions: date keywords + priority levels the parser knows.
    private static let keywords = [
        "today", "tomorrow", "tonight", "later", "end of day", "eod",
        "next week", "this week",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "high", "medium", "low",
    ]

    /// Enter (or Tab while the dropdown is up): accept the highlighted
    /// suggestion, otherwise move to the description.
    private func titleReturnPressed() {
        if !suggestionMatches.isEmpty {
            acceptSuggestion(suggestionMatches[selectedSuggestion])
        } else {
            moveToNotes()
        }
    }

    /// Replace the caret token with the chosen keyword and hide the dropdown.
    private func acceptSuggestion(_ keyword: String) {
        replaceTokenWith = keyword
        replaceTokenRequest += 1
        completionToken = ""
        selectedSuggestion = 0
    }

    private func navigateSuggestion(up: Bool) {
        guard !suggestionMatches.isEmpty else { return }
        let count = suggestionMatches.count
        selectedSuggestion = up ? (selectedSuggestion - 1 + count) % count : (selectedSuggestion + 1) % count
    }

    /// Enter in the title: focus the description (nothing to describe when
    /// the title is empty).
    private func moveToNotes() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        focusedField = .notes
        notesFocusRequest += 1
    }

    /// Same semantics as pressing Return in the description: create the single
    /// reminder (or report what's wrong), clear both fields, keep focus.
    private func submit() {
        guard !saving else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let parsed = NaturalLanguageParser.parse(trimmed, listNames: store.reminderCalendars().map(\.title))
        guard !parsed.isInvalid else {
            saveError = "No title left after parsing"
            return
        }
        Task { await save(parsed) }
    }

    private func save(_ parsed: ParsedReminder) async {
        saving = true
        defer { saving = false }
        do {
            try await createReminder(from: parsed)
            saveError = nil
            title = ""
            notes = ""
            focusedField = .title
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func createReminder(from parsed: ParsedReminder) async throws {
        var title = parsed.title
        if !parsed.listMatched, let token = parsed.listToken {
            title = "@\(token) " + title
        }
        var dueComponents: DateComponents?
        if let due = parsed.dueDate {
            var comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: due)
            if !parsed.hasTime {
                // Date-only parse → all-day reminder.
                comps.hour = nil
                comps.minute = nil
                comps.second = nil
            }
            dueComponents = comps
        }
        var location: EKStructuredLocation?
        if let phrase = parsed.locationPhrase {
            if let loc = await LocationGeocoder.shared.geocode(phrase) {
                location = Self.structuredLocation(title: phrase, location: loc)
            } else {
                title += " at \(phrase)"
            }
        }
        let list = store.resolveList(token: parsed.listToken ?? "")
        // Tags persist as a trailing #-line in notes: public-API compatible,
        // visible in Reminders.app, and matched by the existing #tag search.
        var fullNotes = notes
        if !parsed.tags.isEmpty {
            let tagLine = parsed.tags.map { "#\($0)" }.joined(separator: " ")
            fullNotes = [fullNotes, tagLine].filter { !$0.isEmpty }.joined(separator: "\n")
        }
        try await store.create(title: title, calendar: list.calendar,
                               dueDate: dueComponents, priority: parsed.priority,
                               location: location, notes: fullNotes.isEmpty ? nil : fullNotes)
    }

    /// This SDK exposes only `locationWithTitle:` plus settable properties.
    private static func structuredLocation(title: String, location: CLLocation) -> EKStructuredLocation {
        let structured = EKStructuredLocation()
        structured.title = title
        structured.geoLocation = location
        structured.radius = 100
        return structured
    }
}
