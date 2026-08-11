import EventKit
import SwiftUI

/// Shared reminder row: completion toggle, title, meta line
/// (list color dot + list name + due label, priority "!", location pin).
/// Clicking the text area opens the reminder in Reminders.app.
struct ReminderRowView: View {
    @EnvironmentObject var store: ReminderStore
    let reminder: EKReminder
    /// Keyboard-selection highlight (accent fill, same as the suggestion dropdown).
    var isSelected: Bool = false
    /// Called after the reminder was just completed (for the completion toast).
    var onComplete: ((EKReminder) -> Void)? = nil

    private func toggleComplete() {
        Task { @MainActor in
            await store.toggleCompletion(reminder)
            if reminder.isCompleted { onComplete?(reminder) }
        }
    }

    private var hasLocation: Bool {
        reminder.alarms?.contains { $0.structuredLocation != nil } ?? false
    }

    /// #tags from title + notes (tags remr saves live in notes; older or
    /// external reminders may carry them in the title).
    private var tags: [String] {
        NaturalLanguageParser.extractTags(from: (reminder.title ?? "") + " " + (reminder.notes ?? ""))
    }

    private var isOverdue: Bool {
        guard let due = Calendar.current.date(from: reminder.dueDateComponents ?? DateComponents()) else { return false }
        return due < Calendar.current.startOfDay(for: Date())
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                toggleComplete()
            } label: {
                // Drawn circle (not an SF Symbol) so it is geometrically round
                // at any size — same as Reminders.app's circle.
                ZStack {
                    Circle()
                        .fill(reminder.isCompleted ? Color.accentColor : Color.clear)
                    Circle()
                        .stroke(reminder.isCompleted ? Color.clear : Color.secondary.opacity(0.7), lineWidth: 1.5)
                    if reminder.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 16, height: 16)
                .contentShape(Circle())
                .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(reminder.isCompleted ? "Mark as not completed" : "Mark as completed")
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title)
                    .font(.system(size: 13, weight: .medium))
                    .strikethrough(reminder.isCompleted)
                    .foregroundStyle(reminder.isCompleted ? Color.secondary : Color.primary)
                metaLine
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.16))
            }
        }
        .contentShape(Rectangle())
        // Whole-row tap opens the reminder in Reminders (README/GuideView).
        // Buttons (completion circle, tag chips) consume their own taps, so
        // they never double-fire this gesture.
        .onTapGesture { store.openInReminders(reminder) }
        .contextMenu {
            Button(reminder.isCompleted ? "Mark as Not Completed" : "Mark as Completed") {
                toggleComplete()
            }
            Button("Open in Reminders") { store.openInReminders(reminder) }
            Divider()
            Button("Delete", role: .destructive) {
                Task { await store.deleteReminder(reminder) }
            }
        }
    }

    @ViewBuilder
    private var metaLine: some View {
        HStack(spacing: 4) {
            if reminder.isCompleted {
                if let cd = reminder.completionDate {
                    Text(cd.formatted(date: .omitted, time: .shortened))
                }
            } else {
                if let cal = reminder.calendar {
                    Circle()
                        .fill(Color(cal.color))
                        .frame(width: 8, height: 8)
                    Text(cal.title)
                }
                if let comps = reminder.dueDateComponents, let due = Calendar.current.date(from: comps) {
                    Text("·")
                    if isOverdue {
                        Text(due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                            .foregroundStyle(.red)
                    } else {
                        if let label = Self.dueLabel(for: reminder, calendar: .current), !label.isEmpty {
                            Text(label)
                        }
                    }
                }
            }
            if reminder.priority == 1 {
                Text("!")
                    .font(.caption.bold())
                    .foregroundStyle(.red)
            }
            if hasLocation {
                Image(systemName: "mappin")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(tags, id: \.self) { tag in
                TagChip(name: tag)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// Colored #tag chip; click to filter the list by this tag (click the
    /// active chip again to clear), right-click to pick a color (TagStore).
    private struct TagChip: View {
        @ObservedObject private var tagStore = TagStore.shared
        @ObservedObject private var filterStore = FilterStore.shared
        let name: String

        /// True when this chip's tag is the active list filter.
        private var isActive: Bool {
            filterStore.tag == name.lowercased()
        }

        var body: some View {
            Button {
                filterStore.toggle(name)
            } label: {
                HStack(spacing: 3) {
                    if isActive {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                    }
                    Text("#\(name)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(TagStore.textColor(on: nsColor))
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 3).fill(color))
                .overlay {
                    if isActive {
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Color.accentColor, lineWidth: 1.5)
                    }
                }
            }
            .buttonStyle(.plain)
            .help(isActive ? "Showing only #\(name) — click to clear" : "Filter to #\(name)")
            .contextMenu {
                ForEach(Array(TagStore.palette.enumerated()), id: \.offset) { index, nsColor in
                    Button {
                        tagStore.setColor(for: name, paletteIndex: index)
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(nsColor: nsColor))
                                .frame(width: 10, height: 10)
                            Text(TagStore.colorName(index))
                        }
                    }
                }
            }
        }

        private var nsColor: NSColor {
            TagStore.palette[tagStore.paletteIndex(for: name)]
        }

        private var color: Color {
            Color(nsColor: nsColor)
        }
    }

    /// "Today · 5:00 PM", "Tomorrow · 3:00 PM", "Yesterday · 9:00 AM",
    /// or an absolute date; time omitted for all-day reminders.
    static func dueLabel(for reminder: EKReminder, calendar: Calendar) -> String? {
        guard let comps = reminder.dueDateComponents, let due = calendar.date(from: comps) else { return nil }
        return label(for: due, hasTime: comps.hour != nil, calendar: calendar)
    }

    static func label(for due: Date, hasTime: Bool, calendar: Calendar = .current) -> String {
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!
        let dayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: startOfToday)!
        let time = due.formatted(date: .omitted, time: .shortened)
        switch due {
        case startOfToday..<startOfTomorrow:
            return hasTime ? "Today · \(time)" : "Today"
        case startOfYesterday..<startOfToday:
            return hasTime ? "Yesterday · \(time)" : "Yesterday"
        case startOfTomorrow..<dayAfterTomorrow:
            return hasTime ? "Tomorrow · \(time)" : "Tomorrow"
        default:
            return due.formatted(date: .abbreviated, time: hasTime ? .shortened : .omitted)
        }
    }
}
