import Foundation
import SwiftUI

/// Single-reminder editor: the title parses due date / list / priority /
/// location tokens; a description line appears as you type. Enter in the
/// title moves to the description; Enter in the description creates the
/// reminder; Shift+Enter inserts a newline in the description.
enum SuggestionKind: Equatable {
    case date
    case priority
    case list
    case tag
}

struct SuggestionCandidate: Identifiable, Equatable {
    let id: String
    let label: String
    let replacement: String
    let kind: SuggestionKind
}

/// Single-reminder editor: the title parses due date / list / priority /
/// location tokens; a description line appears as you type. Enter in the
/// title moves to the description; Enter in the description creates the
/// reminder; Shift+Enter inserts a newline in the description.
struct NewReminderView: View {
    @EnvironmentObject var store: ReminderStore
    @EnvironmentObject var settings: SettingsStore
    @State private var title: String
    @State private var notes = ""
    @State private var saving = false
    @State private var saveError: String?
    @State private var parsedPreview: ParsedReminder?
    /// Bumped to move focus from the title into the description.
    @State private var notesFocusRequest = 0
    /// Bumped (with `focusedField`) to grab the title field from outside:
    /// observed `titleFocusRequest` changes and Shift+Tab-back from notes.
    @State private var titleFocusBump = 0
    /// Explicit SwiftUI focus identity — without it, macOS 26's focus system
    /// hands focus to the description the moment it appears.
    @FocusState private var focusedField: EntryField?
    /// Completion context at the title caret and the selected row.
    @State private var completionContext: CompletionContext?
    @State private var selectedSuggestion = 0
    @State private var titleFocused = false
    @State private var replaceTokenRequest = 0
    @State private var replaceTokenWith = ""
    @State private var replaceTokenRange: NSRange?
    /// The currently shown height of the description + parse-preview expansion
    /// region (0 when collapsed). Animated to drive the top-down reveal.
    @State private var expansionHeight: CGFloat = 0
    /// The measured natural height of the region, reported by `HeightReader`.
    @State private var naturalBodyHeight: CGFloat = 0
    /// True once the opening expansion has been animated. Keeps per-keystroke
    /// mirroring from snapping the panel mid-open.
    @State private var isOpen = false
    /// True after the opening animation completes; only then are per-keystroke
    /// height changes mirrored instantly (measurement settling during the
    /// animation is ignored so it can't cancel the motion).
    @State private var mirrorEnabled = false
    /// Measurements smaller than this are treated as layout settling and
    /// ignored. Real per-keystroke changes (a new line ≈ 16pt, a re-wrapped
    /// chip row) are far larger and still mirror instantly.
    private let expansionMirrorTolerance: CGFloat = 4
    /// External bump (MainView): focus the title field (Tab from the list,
    /// Shift+Tab from search, or popover open). Dual mechanism with
    /// `focusedField` + `titleFocusBump` — see `moveToNotes()`.
    var titleFocusRequest: Int = 0
    /// External bump (MainView): focus the notes field (Shift+Tab from
    /// search). Falls back to the title when nothing is typed yet.
    var notesFocusRequestExternal: Int = 0
    /// Tab past the last field (title empty) or from notes → search.
    var onTabForward: (() -> Void)? = nil
    /// Shift+Tab in the title → leave the fields and enter list mode.
    var onTabBackFromTitle: (() -> Void)? = nil
    /// Escape while a text field owns it (dropdown already dismissed).
    var onEscape: (() -> Void)? = nil
    /// Called when the title contains multiple reminder lines.
    var onBulkPreview: ((String) -> Void)? = nil
    /// Called exactly once after the submitted reminder is successfully saved.
    /// Parsing, bulk-preview routing, and failed saves do not invoke it.
    var onCreated: (() -> Void)? = nil
    /// When true (default, in-app popover) the editor is its own glass
    /// surface that grows over the list. When false (quick-add) the editor
    /// sits directly on the panel's glass, so the panel's liquid-glass look
    /// never changes as the description expands.
    var hasOwnGlass: Bool = true
    init(titleFocusRequest: Int = 0,
         notesFocusRequestExternal: Int = 0,
         onTabForward: (() -> Void)? = nil,
         onTabBackFromTitle: (() -> Void)? = nil,
         onEscape: (() -> Void)? = nil,
         onBulkPreview: ((String) -> Void)? = nil,
         onCreated: (() -> Void)? = nil,
         hasOwnGlass: Bool = true) {
        self.titleFocusRequest = titleFocusRequest
        self.notesFocusRequestExternal = notesFocusRequestExternal
        self.onTabForward = onTabForward
        self.onTabBackFromTitle = onTabBackFromTitle
        self.onEscape = onEscape
        self.onBulkPreview = onBulkPreview
        self.onCreated = onCreated
        self.hasOwnGlass = hasOwnGlass
        _title = State(initialValue: "")
    }

    /// The editor's content. With `hasOwnGlass` (in-app popover) the whole
    /// block is one glass surface that grows over the reminder list; without
    /// it (quick-add) the content sits directly on the panel's own glass so
    /// the panel's liquid-glass look never changes as the description expands.
    @ViewBuilder
    private var editorContent: some View {
        let content = VStack(alignment: .leading, spacing: 0) {
            titleField
            if titleFocused, !suggestionMatches.isEmpty {
                suggestionDropdown
            }
            expansionRegion
            if let saveError {
                Text(saveError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }
            // The add area is one glass surface, so adjacent editor pieces do
            // not draw overlapping translucent borders. Its bottom edge stays
            // square against the search row below the input area.
        }
        if hasOwnGlass {
            content.liquidGlassField(in: EntryContainerShape())
        } else {
            content
        }
    }

    var body: some View {
        editorContent
            .onChange(of: title) { _ in
                recomputePreview()
            }
        .onChange(of: hasEntryContent) { _ in
            syncExpansionHeight()
        }
        .onChange(of: naturalBodyHeight) { _ in
            syncExpansionHeight()
        }
        .onChange(of: titleFocusRequest) { _ in
            focusedField = .title
            titleFocusBump += 1
        }
        .onChange(of: notesFocusRequestExternal) { _ in
            if title.isEmpty && notes.isEmpty {
                focusedField = .title
                titleFocusBump += 1
            } else {
                focusedField = .notes
                notesFocusRequest += 1
            }
        }
        .onAppear {
            focusedField = .title
            recomputePreview()
            // The containing window becomes key a moment after this appears;
            // a focus request issued before then can be dropped by the focus
            // system, so re-request once the window is actually key.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = .title
                titleFocusBump += 1
            }
        }
    }

    private func recomputePreview() {
        let now = Date()
        let listNames = store.reminderCalendars().map(\.title)
        parsedPreview = NaturalLanguageParser.parse(title, now: now, calendar: .current, listNames: listNames)
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

    private var titleField: some View {
        ZStack(alignment: .topLeading) {
            ReminderInputView(
                text: $title, refocusOnClear: true, onMoveDown: titleReturnPressed,
                focusRequest: titleFocusBump,
                // Fires when the field appears in a window without already
                // owning first responder — the panel opens with the window
                // not yet key, when a SwiftUI @FocusState request is dropped.
                // The AppKit makeFirstResponder path lands reliably.
                onAppearInWindow: { titleFocusBump += 1 },
                onTokenChange: { context in completionContext = context; selectedSuggestion = 0 },
                onFocusChange: { titleFocused = $0 },
                dropdownActive: titleFocused && !suggestionMatches.isEmpty,
                onNavigate: navigateSuggestion,
                onDismiss: { completionContext = nil },
                onFocusForward: {
                    if title.isEmpty && notes.isEmpty {
                        onTabForward?()
                    } else {
                        focusedField = .notes
                        notesFocusRequest += 1
                    }
                },
                onFocusBack: { onTabBackFromTitle?() },
                onEscape: onEscape,
                replaceTokenRequest: replaceTokenRequest,
                replaceTokenWith: replaceTokenWith,
                replaceTokenRange: replaceTokenRange
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

    private var notesField: some View {
        ZStack(alignment: .topLeading) {
            ReminderInputView(text: $notes, onSubmit: submit, focusRequest: notesFocusRequest,
                              onAppearInWindow: { focusedField = .title },
                              onFocusForward: { onTabForward?() },
                              onFocusBack: { focusedField = .title; titleFocusBump += 1 },
                              onEscape: onEscape)
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

    /// True while any entry surface (description field or parse preview) is
    /// visible. Flips only when the editor gains or loses content — never on
    /// per-keystroke parse-preview refreshes — so it can drive the surface
    /// expansion/collapse animation without animating every preview update.
    private var hasEntryContent: Bool {
        !title.isEmpty || !notes.isEmpty
    }

    /// The description field + parse preview, laid out at their natural height
    /// so it can be measured, but displayed at only `expansionHeight` (0 when
    /// collapsed) and clipped against it. As the height animates, the growing
    /// clip unveils the content top-down in lockstep with the search-row glide.
    private var expansionRegion: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasEntryContent {
                notesField
            }
            if hasEntryContent, let parsedPreview {
                ParsePreviewView(draft: ReminderDraft.fromParsed(
                    parsedPreview,
                    notes: notes,
                    calendar: parsedPreview.listToken.flatMap { store.resolveList(token: $0).calendar }
                ))
            }
        }
        .fixedSize(horizontal: false, vertical: true)        // natural height, for measurement
        .background(HeightReader { naturalBodyHeight = $0 }) // measures the fixedSize content
        .frame(height: expansionHeight, alignment: .top)     // ideal == expansionHeight (see below)
        .clipped()
    }

    /// One animation drives the expansion — either SwiftUI (in-app: the
    /// `withAnimation` transaction also reflows the search row) or AppKit
    /// (quick-add: the hosting window's resize performs the reveal). The two
    /// are never mixed, so the panel edge and the revealed content stay
    /// frame-locked. Per-keystroke growth of the measured natural height is
    /// mirrored instantly, never animated; measurement *settling* (a couple of
    /// points over the first layout passes) is ignored so the panel never
    /// wobbles.
    private func syncExpansionHeight() {
        if hasEntryContent {
            // The notes/preview just appeared; `naturalBodyHeight` is still 0
            // for this pass. Wait for the measurement callback to set the
            // height — acting on 0 now would pop the region to its final
            // height on the next pass.
            guard naturalBodyHeight > 0 else { return }

            if !isOpen {
                isOpen = true
                mirrorEnabled = false
                withAnimation(.easeInOut(duration: 0.2)) {
                    expansionHeight = naturalBodyHeight
                }
                // Let the opening animation finish before per-keystroke
                // instant mirroring kicks in.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    if isOpen { mirrorEnabled = true }
                }
            } else if abs(naturalBodyHeight - expansionHeight) >= expansionMirrorTolerance {
                if mirrorEnabled {
                    // Already open: mirror per-keystroke growth instantly.
                    expansionHeight = naturalBodyHeight // no animation
                } else {
                    // Still opening and the first measurement was meaningfully
                    // off: re-target the in-flight animation smoothly instead
                    // of snapping.
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expansionHeight = naturalBodyHeight
                    }
                }
            }
        } else if isOpen {
            isOpen = false
            mirrorEnabled = false
            if expansionHeight > 0 {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expansionHeight = 0
                }
            }
        }
    }

    /// Grows with the description (one line ≈ 32pt, capped at ~5 lines) so a
    /// fresh box is compact instead of a tall empty slab.
    private var notesFieldHeight: CGFloat {
        let lines = max(1, notes.split(whereSeparator: { $0.isNewline }).count)
        return min(16 + CGFloat(lines) * 16, 96)
    }

    /// Date/priority keywords followed by matching real lists and tags. The
    /// input view supplies a UTF-16-safe range, so every candidate replaces
    /// exactly the token that produced it.
    private var suggestionMatches: [SuggestionCandidate] {
        guard let context = completionContext else { return [] }
        return Self.suggestionCandidates(
            for: context.text,
            listTitles: store.reminderCalendars().map(\.title),
            tags: store.allTags()
        )
    }

    /// Keyword/`@`/`#` candidates matching the caret token. Every kind
    /// excludes the exact match, so accepting a suggestion (which leaves the
    /// completed token in the field) closes the dropdown instead of re-
    /// proposing the very item just inserted.
    static func suggestionCandidates(for token: String, listTitles: [String], tags: [String]) -> [SuggestionCandidate] {
        guard !token.isEmpty else { return [] }
        let lower = token.lowercased()
        var candidates: [SuggestionCandidate] = []

        if token.hasPrefix("@") {
            let query = String(token.dropFirst()).trimmingCharacters(in: .whitespaces).lowercased()
            guard !query.isEmpty else { return [] }
            var seen = Set<String>()
            for title in listTitles {
                let key = title.lowercased()
                guard key != query, key.hasPrefix(query), seen.insert(key).inserted else { continue }
                candidates.append(SuggestionCandidate(id: "list:\(key)", label: "@\(title)", replacement: "@\(title)", kind: .list))
            }
        } else if token.hasPrefix("#") {
            let query = String(token.dropFirst()).lowercased()
            guard !query.isEmpty else { return [] }
            var seen = Set<String>()
            for tag in tags {
                let key = tag.lowercased()
                guard key != query, key.hasPrefix(query), seen.insert(key).inserted else { continue }
                candidates.append(SuggestionCandidate(id: "tag:\(key)", label: "#\(tag)", replacement: "#\(tag)", kind: .tag))
            }
        } else {
            guard token.count >= 2 else { return [] }
            for keyword in Self.dateKeywords where keyword.lowercased().hasPrefix(lower) && keyword.lowercased() != lower {
                candidates.append(SuggestionCandidate(id: "date:\(keyword)", label: keyword, replacement: keyword, kind: .date))
            }
            for keyword in Self.priorityKeywords where keyword.lowercased().hasPrefix(lower) && keyword.lowercased() != lower {
                candidates.append(SuggestionCandidate(id: "priority:\(keyword)", label: keyword, replacement: keyword, kind: .priority))
            }
        }
        return Array(candidates.prefix(8))
    }

    private var suggestionDropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Suggestions")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text("Return to insert")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)

            Divider()
                .opacity(0.45)

            VStack(spacing: 2) {
                ForEach(Array(suggestionMatches.enumerated()), id: \.offset) { index, candidate in
                    Button {
                        acceptSuggestion(candidate)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: suggestionIcon(for: candidate.kind))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(suggestionTint(for: candidate.kind))
                                .frame(width: 24, height: 24)
                                .background(
                                    suggestionTint(for: candidate.kind).opacity(0.14),
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                                )

                            VStack(alignment: .leading, spacing: 1) {
                                Text(candidate.label)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(suggestionKindTitle(for: candidate.kind))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 8)

                            if index == selectedSuggestion {
                                Image(systemName: "return")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(index == selectedSuggestion
                                      ? Color.accentColor.opacity(0.15)
                                      : Color.clear)
                                .overlay {
                                    if index == selectedSuggestion {
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
                                    }
                                }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(candidate.label)
                    .accessibilityHint("Insert suggestion")
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .liquidGlassField(in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func suggestionIcon(for kind: SuggestionKind) -> String {
        switch kind {
        case .date: return "calendar"
        case .priority: return "exclamationmark.circle"
        case .list: return "list.bullet"
        case .tag: return "number"
        }
    }

    private func suggestionKindTitle(for kind: SuggestionKind) -> String {
        switch kind {
        case .date: return "Date"
        case .priority: return "Priority"
        case .list: return "List"
        case .tag: return "Tag"
        }
    }

    private func suggestionTint(for kind: SuggestionKind) -> Color {
        switch kind {
        case .date: return .blue
        case .priority: return .orange
        case .list: return .green
        case .tag: return .purple
        }
    }

    private static let dateKeywords = [
        "today", "tomorrow", "tonight", "later", "end of day", "eod",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
    ]
    private static let priorityKeywords = ["high", "medium", "low"]

    /// Enter (or Tab while the dropdown is up): accept the highlighted
    /// suggestion, otherwise move to the description.
    private func titleReturnPressed() {
        if !suggestionMatches.isEmpty {
            acceptSuggestion(suggestionMatches[selectedSuggestion])
        } else {
            moveToNotes()
        }
    }

    private func acceptSuggestion(_ candidate: SuggestionCandidate) {
        replaceTokenWith = candidate.replacement
        replaceTokenRange = completionContext?.range
        replaceTokenRequest += 1
        completionContext = nil
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
    /// Title/notes are snapshotted before the async save so text typed while
    /// the save is in flight survives (the clear is conditional on the fields
    /// still holding the submitted text).
    private func submit() {
        guard !saving else { return }
        if title.contains("\n") {
            onBulkPreview?(title)
            return
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let now = Date()
        let listNames = store.reminderCalendars().map(\.title)
        let parsed = NaturalLanguageParser.parse(trimmed, now: now, calendar: .current, listNames: listNames)
        parsedPreview = parsed
        guard !parsed.isInvalid else {
            saveError = "No title left after parsing"
            return
        }
        let titleAtSubmit = trimmed
        let notesAtSubmit = notes
        saving = true
        Task { @MainActor in await save(parsed, titleAtSubmit: titleAtSubmit, notesAtSubmit: notesAtSubmit) }
    }

    /// `save` touches @State (saving, title, notes, saveError, focusedField);
    /// pin it to the main actor explicitly so the mutations never run on a
    /// background executor on SDKs where View isn't MainActor-isolated yet.
    @MainActor
    private func save(_ parsed: ParsedReminder, titleAtSubmit: String, notesAtSubmit: String) async {
        defer { saving = false }
        do {
            let locationMessage = try await createReminder(from: parsed, notes: notesAtSubmit)
            onCreated?()
            saveError = locationMessage
            if title == titleAtSubmit { title = "" }
            if notes == notesAtSubmit { notes = "" }
            focusedField = .title
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func createReminder(from parsed: ParsedReminder, notes notesAtSubmit: String) async throws -> String? {
        var draft = ReminderDraft.fromParsed(parsed, notes: notesAtSubmit, calendar: parsed.listToken.flatMap { store.resolveList(token: $0).calendar })
        var saveMessage: String?

        if case .unresolved(let phrase) = draft.location {
            if let located = await LocationGeocoder.shared.geocode(phrase) {
                draft.location = .resolved(DeletedLocation(
                    title: located.title,
                    latitude: located.latitude,
                    longitude: located.longitude,
                    radius: 100
                ))
            } else {
                draft.title += " at \(phrase)"
                draft.location = .none
                saveMessage = "Couldn't find location “\(phrase)” — added it to the title"
            }
        }

        try await store.create(from: draft)
        return saveMessage
    }
}

/// Reports the natural height of the view it's backgrounded onto, as a
/// preference-free callback. Fires on appear and whenever that height changes.
struct HeightReader: View {
    let onChange: (CGFloat) -> Void
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { onChange(proxy.size.height) }
                .onChange(of: proxy.size.height) { _ in onChange(proxy.size.height) }
        }
    }
}
