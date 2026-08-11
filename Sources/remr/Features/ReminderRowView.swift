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
    /// Called when the row is clicked while not selected (first click selects,
    /// second click opens in Reminders).
    var onSelect: (() -> Void)? = nil
    /// MainView owns every EventKit mutation so completion and deletion share
    /// the same error/recovery behavior as keyboard actions.
    var onToggleCompletion: ((EKReminder) -> Void)? = nil
    var onDelete: ((EKReminder) -> Void)? = nil
    var onEdit: ((EKReminder) -> Void)? = nil
    var onSnooze: ((EKReminder) -> Void)? = nil
    var onDuplicate: ((EKReminder) -> Void)? = nil
    var onMoveToList: ((EKReminder, String?) -> Void)? = nil
    var onCopyTitle: ((EKReminder) -> Void)? = nil

    private func toggleComplete() {
        onToggleCompletion?(reminder)
    }

    private var hasLocation: Bool {
        reminder.alarms?.contains { $0.structuredLocation != nil } ?? false
    }

    /// The location's display name (the phrase typed at creation), when the
    /// reminder carries a geofenced alarm with a title.
    private var locationTitle: String? {
        reminder.alarms?
            .compactMap { $0.structuredLocation?.title }
            .first { !$0.isEmpty }
    }

    /// #tags from title + notes (tags remr saves live in notes; older or
    /// external reminders may carry them in the title).
    private var tags: [String] {
        NaturalLanguageParser.extractTags(from: (reminder.title ?? "") + " " + (reminder.notes ?? ""))
    }
    private var isOngoing: Bool {
        NaturalLanguageParser.isOngoing(title: reminder.title, notes: reminder.notes)
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
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1))
            }
        }
        .contentShape(Rectangle())
        // First click selects the row (showing the highlight); clicking the
        // selected row again opens it in Reminders. Buttons (completion
        // circle, tag chips) consume their own taps, so they never
        // double-fire this gesture.
        .onTapGesture {
            if isSelected {
                store.openInReminders(reminder)
            } else {
                onSelect?()
            }
        }
        .contextMenu {
            Button(reminder.isCompleted ? "Mark as Not Completed" : "Mark as Completed") {
                toggleComplete()
            }
            if !reminder.isCompleted {
                Button(isOngoing ? "Remove from Ongoing" : "Mark as Ongoing") {
                    Task { @MainActor in
                        await store.setOngoing(reminder, enabled: !isOngoing)
                    }
                }
            }

            Button("Open in Reminders") { store.openInReminders(reminder) }
            Button("Edit") { onEdit?(reminder) }
            if !reminder.isCompleted {
                Button("Snooze") { onSnooze?(reminder) }
            }

            Menu("Move to List") {
                Button("Default list") {
                    onMoveToList?(reminder, nil)
                }
                Divider()
                ForEach(store.reminderCalendars(), id: \.calendarIdentifier) { calendar in
                    Button(calendar.title) {
                        onMoveToList?(reminder, calendar.calendarIdentifier)
                    }
                }
            }
            Button("Duplicate") { onDuplicate?(reminder) }
            Button("Copy Title") { onCopyTitle?(reminder) }
            Divider()
            Button("Delete", role: .destructive) {
                onDelete?(reminder)
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
                        Text(Self.dateLabel(for: due, calendar: .current))
                        if comps.hour != nil {
                            Text(due.formatted(date: .omitted, time: .shortened))
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
                if let locationTitle {
                    Text(locationTitle)
                        .lineLimit(1)
                }
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

    /// "Today", "Tomorrow", "Yesterday", or an absolute date. The time is
    /// rendered separately by the row (only for timed reminders).
    static func dateLabel(for due: Date, calendar: Calendar = .current) -> String {
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!
        let dayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: startOfToday)!
        switch due {
        case startOfToday..<startOfTomorrow:
            return "Today"
        case startOfYesterday..<startOfToday:
            return "Yesterday"
        case startOfTomorrow..<dayAfterTomorrow:
            return "Tomorrow"
        default:
            return due.formatted(date: .abbreviated, time: .omitted)
        }
    }
}
