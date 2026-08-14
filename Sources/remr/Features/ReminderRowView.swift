import EventKit
import SwiftUI

/// Shared reminder row: completion toggle, title, meta line
/// (list color dot + list name + due label, priority "!", location pin,
/// recurrence summary).
/// Single-click selects; double-clicking opens the reminder in Reminders.app.
struct ReminderRowView: View {
    @EnvironmentObject var store: ReminderStore
    let reminder: EKReminder
    /// Keyboard/mouse-selection highlight (accent fill, same as the suggestion dropdown).
    var isSelected: Bool = false
    /// Called when the row is single-clicked while unselected (selects it).
    var onSelect: (() -> Void)? = nil
    /// Called when the row is double-clicked (opens it in Reminders.app).
    var onOpen: (() -> Void)? = nil
    /// MainView owns every EventKit mutation so completion and deletion share
    /// the same error/recovery behavior as keyboard actions. The second
    /// argument fires once the mutation has settled (success or failure), so
    /// the row can clear its tick state; on success the row keeps its checked
    /// appearance because the reminder's own `isCompleted` is now true.
    var onToggleCompletion: ((EKReminder, @escaping () -> Void) -> Void)? = nil
    var onDelete: ((EKReminder) -> Void)? = nil
    var onEdit: ((EKReminder) -> Void)? = nil
    var onSnooze: ((EKReminder) -> Void)? = nil
    var onDuplicate: ((EKReminder) -> Void)? = nil
    var onMoveToList: ((EKReminder, String?) -> Void)? = nil
    var onCopyTitle: ((EKReminder) -> Void)? = nil
    @State private var isHovered = false
    /// True while the completion tick is playing; gates re-entry and drives
    /// the circle fill/checkmark animation before the store mutation.
    @State private var isCompleting = false

    private func toggleComplete() {
        guard !isCompleting else { return }
        if reminder.isCompleted {
            // Restoring: no tick, hand straight off.
            onToggleCompletion?(reminder, {})
        } else {
            // Play the tick (fill + checkmark draw), then hand off; the reset
            // closure fires once the store mutation settles either way.
            isCompleting = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                onToggleCompletion?(reminder) {
                    self.isCompleting = false
                }
            }
        }
    }

    /// The circle's checked appearance: either already completed in the data,
    /// or mid-tick.
    private var showCompleted: Bool { reminder.isCompleted || isCompleting }
    private var checkmarkProgress: CGFloat { showCompleted ? 1 : 0 }

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

    /// "Repeats weekly", "Repeats every 2 weeks", … from a recurrence rule.
    /// Rules set in Reminders.app surface here; remr doesn't create them yet.
    private var recurrenceSummary: String? {
        reminder.recurrenceRules?.first.flatMap(Self.recurrenceSummary(for:))
    }

    /// Formats a single recurrence rule; nil for unknown frequencies.
    static func recurrenceSummary(for rule: EKRecurrenceRule) -> String? {
        switch rule.frequency {
        case .daily:
            return rule.interval == 1 ? "Repeats daily" : "Repeats every \(rule.interval) days"
        case .weekly:
            return rule.interval == 1 ? "Repeats weekly" : "Repeats every \(rule.interval) weeks"
        case .monthly:
            return rule.interval == 1 ? "Repeats monthly" : "Repeats every \(rule.interval) months"
        case .yearly:
            return rule.interval == 1 ? "Repeats yearly" : "Repeats every \(rule.interval) years"
        @unknown default:
            return nil
        }
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
                // at any size — same as Reminders.app's circle. On completion
                // the fill sweeps to accent and the checkmark draws itself in.
                ZStack {
                    Circle()
                        .fill(showCompleted ? Color.accentColor : Color.clear)
                    Circle()
                        .stroke(showCompleted
                                ? Color.clear
                                : (isSelected ? Color.accentColor : Color.secondary.opacity(0.7)),
                                lineWidth: 1.5)
                    if showCompleted {
                        CheckmarkShape()
                            .trim(from: 0, to: checkmarkProgress)
                            .stroke(Color.white,
                                    style: StrokeStyle(lineWidth: 1.7,
                                                       lineCap: .round,
                                                       lineJoin: .round))
                            .animation(.easeOut(duration: 0.14), value: checkmarkProgress)
                    }
                }
                .frame(width: 16, height: 16)
                .contentShape(Circle())
                .frame(width: 22, height: 22)
                .animation(.easeOut(duration: 0.1), value: showCompleted)
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
            rowSelectionHighlight(selected: isSelected, hovered: isHovered)
        }
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .animation(.easeOut(duration: 0.1), value: isHovered)
        // Single click selects an unselected row (clicking the selected row
        // again keeps the selection — no accidental open). Double-click opens
        // the reminder in Reminders. Buttons (completion circle, tag chips)
        // consume their own taps, so they never double-fire these gestures.
        .onTapGesture {
            if !isSelected {
                onSelect?()
            }
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            onOpen?()
        })
        .onHover { hovering in
            isHovered = hovering
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
            if let recurrenceSummary {
                Text("·")
                Image(systemName: "arrow.clockwise")
                    .font(.caption2)
                Text(recurrenceSummary)
                    .lineLimit(1)
            }
            if reminder.priority == 1 {
                Text("!")
                    .font(.caption.bold())
                    .foregroundStyle(.red)
            } else if reminder.priority == 5 {
                Text("!")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            } else if reminder.priority == 9 {
                Text("!")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
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
                .liquidGlassChip(in: RoundedRectangle(cornerRadius: 3), tint: color, filled: true)
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

/// The completion checkmark as a stroked path so it can draw itself in via
/// `trim` during the completion tick.
struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.22, y: rect.height * 0.52))
        path.addLine(to: CGPoint(x: rect.width * 0.42, y: rect.height * 0.72))
        path.addLine(to: CGPoint(x: rect.width * 0.8, y: rect.height * 0.28))
        return path
    }
}
