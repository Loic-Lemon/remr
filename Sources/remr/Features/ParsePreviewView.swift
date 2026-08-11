import SwiftUI

/// A write-free presentation of parser output. This view intentionally receives
/// a draft rather than touching EventKit or attempting location resolution.
struct ParsePreviewView: View {
    let draft: ReminderDraft

    @ObservedObject private var tagStore = TagStore.shared

    init(draft: ReminderDraft) {
        self.draft = draft
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            chips
            diagnostics
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var chips: some View {
        // The entered title remains in the editor above; preview only shows
        // metadata parsed from it so the chips are unambiguously actionable.
        if let dueDate = draft.dueDate {
            let dateText = ReminderRowView.dateLabel(for: dueDate)
            let text = draft.hasTime
                ? "\(dateText) · \(dueDate.formatted(date: .omitted, time: .shortened))"
                : dateText
            previewChip(text)
        }
        if let calendarTitle = draft.calendarTitle, !calendarTitle.isEmpty {
            previewChip("@\(calendarTitle)")
        }
        if draft.priority != 0 {
            previewChip(priorityLabel)
        }
        if case .unresolved(let phrase) = draft.location, !phrase.isEmpty {
            previewChip("at \(phrase)")
        }
        if case .resolved(let location) = draft.location, !location.title.isEmpty {
            previewChip("at \(location.title)")
        }
        if !draft.tags.isEmpty {
            HStack(spacing: 4) {
                ForEach(draft.tags, id: \.self) { tag in
                    tagChip(tag)
                }
            }
        }
    }

    @ViewBuilder
    private var diagnostics: some View {
        ForEach(Array(draft.diagnostics.enumerated()), id: \.offset) { _, diagnostic in
            switch diagnostic {
            case .emptyTitle:
                Text("Add a title")
                    .foregroundStyle(.orange)
            case .unmatchedList(let token):
                Text("List “@\(token)” was not found")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var priorityLabel: String {
        switch draft.priority {
        case 1: return "High priority"
        case 5: return "Medium priority"
        case 9: return "Low priority"
        default: return "Priority"
        }
    }

    private func previewChip(_ text: String) -> some View {
        Text(text)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.secondary.opacity(0.14)))
    }

    private func tagChip(_ tag: String) -> some View {
        Text("#\(tag)")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(tagStore.color(for: tag)))
    }
}
