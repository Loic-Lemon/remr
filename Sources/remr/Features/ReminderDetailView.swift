import CoreLocation
import EventKit
import MapKit
import SwiftUI

/// Read-only detail page for a reminder, shown in the main popover. Edit and
/// "View in Reminders" are the primary actions; a resolved location renders
/// on a map.
struct ReminderDetailView: View {
    @EnvironmentObject private var store: ReminderStore
    @ObservedObject private var tagStore = TagStore.shared

    let onClose: () -> Void
    let onEdit: (EKReminder) -> Void
    var onDuplicate: (EKReminder) -> Void = { _ in }
    var onMoveToList: (EKReminder, String?) -> Void = { _, _ in }
    var onDelete: (EKReminder) -> Void = { _ in }
    var onCopyTitle: (EKReminder) -> Void = { _ in }

    @State private var current: EKReminder
    @State private var togglingCompletion = false
    @State private var errorMessage: String?
    @State private var showSnoozePicker = false

    init(reminder: EKReminder,
         onClose: @escaping () -> Void,
         onEdit: @escaping (EKReminder) -> Void,
         onDuplicate: @escaping (EKReminder) -> Void = { _ in },
         onMoveToList: @escaping (EKReminder, String?) -> Void = { _, _ in },
         onDelete: @escaping (EKReminder) -> Void = { _ in },
         onCopyTitle: @escaping (EKReminder) -> Void = { _ in }) {
        self.onClose = onClose
        self.onEdit = onEdit
        self.onDuplicate = onDuplicate
        self.onMoveToList = onMoveToList
        self.onDelete = onDelete
        self.onCopyTitle = onCopyTitle
        _current = State(initialValue: reminder)
    }

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.45)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    hero
                    if !tags.isEmpty {
                        section("Tags") { tagsBlock }
                    }
                    if let notes = current.notes, !notes.isEmpty {
                        section("Description") { notesBlock(notes) }
                    }
                    if let location = structuredLocation {
                        section("Location") { locationCard(location) }
                    }
                }
                .padding(16)
            }
            .clipped()
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
            }
            Divider().opacity(0.45)
            // Pinned meta line: stays at the bottom regardless of scroll.
            HStack {
                Text("Created \(createdLabel)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            footer
        }
        .liquidGlassPane(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Reminder details")
        .onExitCommand(perform: onClose)
        .popover(isPresented: $showSnoozePicker, arrowEdge: .top) {
            SnoozeDatePickerView(initialDate: dueDate ?? defaultSnoozeDate(),
                                 initialHasTime: !isAllDay,
                                 onCancel: { showSnoozePicker = false },
                                 onSave: { date, hasTime in
                                     showSnoozePicker = false
                                     saveSnooze(until: date, hasTime: hasTime)
                                 })
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                onClose()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.primary.opacity(0.07)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Back")
            Spacer()
            Text("Reminder")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Color.clear
                .frame(width: 26, height: 26)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(current.title ?? "")
                .font(.title2.weight(.semibold))
                .strikethrough(isCompleted)
                .foregroundStyle(isCompleted ? Color.secondary : Color.primary)
                .textSelection(.enabled)
            if let due = dueDate {
                dueCard(due)
            }
            if isCompleted {
                statusChip(systemImage: "checkmark.circle.fill",
                           text: completionLabel,
                           tint: .green)
            }
            if hasMetaChips {
                HStack(spacing: 6) {
                    if let list = current.calendar {
                        metaChip(text: list.title, dotColor: calendarColor)
                    }
                    if let priority = priorityLabel {
                        metaChip(text: priority, icon: "flag.fill")
                    }
                    if let recurrence = recurrenceSummary {
                        metaChip(text: recurrence, icon: "repeat")
                    }
                }
            }
        }
    }

    /// Mini week strip (the due date's week) + date line + countdown badge.
    /// A "where we are" line under the week shows an arrow pointing in the
    /// direction of today, whenever today isn't the due day itself.
    private func dueCard(_ due: Date) -> some View {
        let weekStart = CalendarGridMath.startOfWeek(for: due, calendar: calendar)
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)!
        let today = Date()
        let todayBeforeWeek = calendar.startOfDay(for: today) < weekStart
        let todayAfterWeek = calendar.startOfDay(for: today) > weekEnd
        let todayIsDueDay = calendar.isDate(today, inSameDayAs: due)
        return VStack(alignment: .leading, spacing: 8) {
            MiniWeekView(calendar: calendar, date: due, today: today)
            HStack {
                if todayBeforeWeek {
                    sideMarker(.before)
                    Spacer(minLength: 0)
                } else if todayAfterWeek {
                    Spacer(minLength: 0)
                    sideMarker(.after)
                } else if !todayIsDueDay {
                    Spacer(minLength: 0)
                    sideMarker(.sameWeek)
                    Spacer(minLength: 0)
                }
            }
            HStack(spacing: 8) {
                Text(dueText(due))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(isOverdue ? Color.red : Color.primary)
                if !isCompleted, let countdown = countdown {
                    countdownBadge(countdown)
                }
            }
        }
    }

    private enum TodaySide {
        case before   // today is in an earlier week
        case sameWeek // today is on the strip, but not the due day
        case after    // today is in a later week
    }

    /// "Where we are" line: an arrow pointing in the direction of today plus
    /// today's date. Before → arrow left (today is off to the left, like a
    /// scroll edge); after → arrow right; same week → arrow up at the strip.
    private func sideMarker(_ side: TodaySide) -> some View {
        HStack(spacing: 5) {
            if side == .before {
                Image(systemName: "arrow.left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            } else if side == .sameWeek {
                Image(systemName: "arrow.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
            Text("Today")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            if side == .after {
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .help(helpText(for: side))
    }

    private func helpText(for side: TodaySide) -> String {
        switch side {
        case .before:
            return "Today (\(todayLabel)) is before this week — the reminder is still ahead"
        case .sameWeek:
            return "Today (\(todayLabel)) is in this week — the reminder is \(isOverdue ? "overdue" : "coming up")"
        case .after:
            return "Today (\(todayLabel)) is after this week — the reminder is overdue"
        }
    }

    private var todayLabel: String {
        Date().formatted(.dateTime.month(.abbreviated).day())
    }

    private func countdownBadge(_ countdown: Countdown) -> some View {
        HStack(spacing: 4) {
            Image(systemName: countdown.isOverdue ? "arrow.down.left" : "arrow.up.right")
                .font(.caption2)
            Text(countdown.label)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .liquidGlassChip(tint: countdown.isOverdue ? .red : .green)
        .help(countdown.isOverdue ? "Overdue" : "Due")
    }

    /// "in 3 days" / "tomorrow" / "in 4 hours" / "2 days overdue" / "yesterday".
    private enum Countdown {
        case futureMinutes(Int), futureHours(Int), futureDays(Int)
        case overdueMinutes(Int), overdueHours(Int), overdueDays(Int)

        var isOverdue: Bool {
            switch self {
            case .futureMinutes, .futureHours, .futureDays: return false
            default: return true
            }
        }

        var label: String {
            switch self {
            case .futureMinutes(let m): return m == 1 ? "in 1 min" : "in \(m) min"
            case .futureHours(let h): return h == 1 ? "in 1 hour" : "in \(h) hours"
            case .futureDays(let d): return d == 1 ? "tomorrow" : "in \(d) days"
            case .overdueMinutes(let m): return m == 1 ? "1 min overdue" : "\(m) min overdue"
            case .overdueHours(let h): return h == 1 ? "1 hour overdue" : "\(h) hours overdue"
            case .overdueDays(let d): return d == 1 ? "yesterday" : "\(d) days overdue"
            }
        }
    }

    private var countdown: Countdown? {
        guard let due = dueDate, !isCompleted else { return nil }
        let now = Date()
        let seconds = due.timeIntervalSince(now)
        let dayDiff = calendar.dateComponents([.day],
                                              from: calendar.startOfDay(for: now),
                                              to: calendar.startOfDay(for: due)).day ?? 0
        if seconds > 0 {
            if dayDiff >= 1 { return .futureDays(dayDiff) }
            if seconds < 3600 { return .futureMinutes(max(Int(ceil(seconds / 60)), 1)) }
            return .futureHours(max(Int(ceil(seconds / 3600)), 1))
        }
        let past = -seconds
        if dayDiff <= -1 { return .overdueDays(-dayDiff) }
        if past < 3600 { return .overdueMinutes(max(Int(ceil(past / 60)), 1)) }
        return .overdueHours(max(Int(ceil(past / 3600)), 1))
    }

    private func statusChip(systemImage: String, text: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption2)
            Text(text)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .liquidGlassChip(tint: tint)
    }

    private func metaChip(text: String, icon: String? = nil, dotColor: Color? = nil) -> some View {
        HStack(spacing: 5) {
            if let dotColor {
                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)
            }
            if let icon {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(text)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }

    // MARK: - Sections

    private func section<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.4)
            content()
        }
    }

    private var tagsBlock: some View {
        HStack(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text("#\(tag)")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .liquidGlassChip(tint: tagStore.color(for: tag), filled: true)
            }
        }
    }

    private func notesBlock(_ notes: String) -> some View {
        Text(notes)
            .font(.callout)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
    }

    private func locationCard(_ location: EKStructuredLocation) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let coordinate = coordinate {
                LocationMapView(coordinate: coordinate, title: location.title ?? "")
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                    .frame(height: 60)
            }
            HStack(spacing: 6) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.red)
                Text(location.title ?? "Location")
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "bell.badge.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("Notifies when you arrive")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(8)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                toggleCompletion()
            } label: {
                HStack(spacing: 8) {
                    completionCircle
                    Text(isCompleted ? "Restore" : "Complete")
                        .font(.callout.weight(.medium))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(togglingCompletion)
            .help(isCompleted ? "Mark as not completed" : "Mark as completed")
            Spacer()
            Button {
                store.openInReminders(current)
            } label: {
                Label("View in Reminders", systemImage: "externaldrive")
            }
            .liquidGlassButtonStyle(.bordered)
            Button {
                onEdit(current)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .liquidGlassButtonStyle(.borderedProminent, prominent: true)
            Menu {
                snoozeMenuItems(for: current, actions: snoozeActions)
                Divider()
                Button("Duplicate") { onDuplicate(current) }
                Button("Copy Title") { onCopyTitle(current) }
                Menu("Move to List") {
                    Button("Default list") { onMoveToList(current, nil) }
                    Divider()
                    ForEach(store.reminderCalendars(), id: \.calendarIdentifier) { calendar in
                        Button(calendar.title) { onMoveToList(current, calendar.calendarIdentifier) }
                    }
                }
                Divider()
                Button("Delete", role: .destructive) { onDelete(current) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("More actions")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// The drawn completion circle matching the main list rows: accent fill
    /// sweeps in and the checkmark draws itself on completion.
    private var completionCircle: some View {
        ZStack {
            Circle()
                .fill(isCompleted ? Color.accentColor : Color.clear)
            Circle()
                .stroke(isCompleted ? Color.clear : Color.secondary.opacity(0.7), lineWidth: 1.5)
            CheckmarkShape()
                .trim(from: 0, to: isCompleted ? 1 : 0)
                .stroke(Color.white,
                        style: StrokeStyle(lineWidth: 1.7,
                                           lineCap: .round,
                                           lineJoin: .round))
                .animation(.easeOut(duration: 0.14), value: isCompleted)
        }
        .frame(width: 18, height: 18)
        .contentShape(Circle())
        .frame(width: 24, height: 24)
        .animation(.easeOut(duration: 0.14), value: isCompleted)
    }

    // MARK: - Derived

    private var isCompleted: Bool { current.isCompleted }

    private var completionLabel: String {
        if let completion = current.completionDate {
            return "Completed \(completion.formatted(date: .abbreviated, time: .shortened))"
        }
        return "Completed"
    }

    private var dueDate: Date? {
        current.dueDateComponents.flatMap { calendar.date(from: $0) }
    }

    private func dueText(_ due: Date) -> String {
        isAllDay
            ? due.formatted(date: .abbreviated, time: .omitted) + " · All day"
            : due.formatted(date: .abbreviated, time: .shortened)
    }

    private var isAllDay: Bool {
        current.dueDateComponents?.hour == nil
    }

    private var isOverdue: Bool {
        guard let due = dueDate, !isCompleted else { return false }
        return CalendarGridMath.isOverdue(due, now: Date(), calendar: calendar)
    }

    private var hasMetaChips: Bool {
        current.calendar != nil || priorityLabel != nil || recurrenceSummary != nil
    }

    private var tags: [String] {
        Array(Set(NaturalLanguageParser.extractTags(from: (current.title ?? "") + " " + (current.notes ?? ""))
            .map { $0.lowercased() })).sorted()
    }

    private var calendarColor: Color {
        guard let cg = current.calendar?.cgColor else { return .accentColor }
        return Color(cgColor: cg)
    }

    private var priorityLabel: String? {
        switch current.priority {
        case 0: return nil
        case 1...4: return "!"
        case 5: return "!!"
        default: return "!!!"
        }
    }

    private var recurrenceSummary: String? {
        guard let rule = current.recurrenceRules?.first else { return nil }
        let interval = max(rule.interval, 1)
        switch rule.frequency {
        case .daily:
            return interval == 1 ? "Every day" : "Every \(interval) days"
        case .weekly:
            if let weekday = rule.daysOfTheWeek?.first?.dayOfTheWeek {
                let name = calendar.weekdaySymbols[weekday.rawValue - 1]
                return interval == 1 ? "Every \(name)" : "Every \(interval) weeks on \(name)"
            }
            return interval == 1 ? "Every week" : "Every \(interval) weeks"
        case .monthly:
            return interval == 1 ? "Every month" : "Every \(interval) months"
        case .yearly:
            return interval == 1 ? "Every year" : "Every \(interval) years"
        @unknown default:
            return "Repeats"
        }
    }

    private var structuredLocation: EKStructuredLocation? {
        current.alarms?.first { $0.structuredLocation != nil }?.structuredLocation
    }

    private var coordinate: CLLocationCoordinate2D? {
        structuredLocation?.geoLocation?.coordinate
    }

    private var createdLabel: String {
        (current.creationDate ?? Date()).formatted(date: .abbreviated, time: .omitted)
    }

    // MARK: - Actions

    private var snoozeActions: CalendarActions {
        CalendarActions(onSnooze: applySnooze,
                        onCustomSnooze: { _ in showSnoozePicker = true },
                        onClearDue: { _ in clearDue() })
    }

    private func applySnooze(_ reminder: EKReminder, _ choice: SnoozeChoice) {
        guard !reminder.isCompleted else { return }
        guard let result = SnoozeCalculator.date(for: choice, now: Date(), calendar: calendar) else {
            errorMessage = "Couldn't calculate snooze date"
            return
        }
        saveSnooze(until: result.date, hasTime: result.hasTime)
    }

    private func clearDue() {
        saveSnooze(until: nil, hasTime: false)
    }

    private func saveSnooze(until date: Date?, hasTime: Bool) {
        Task { @MainActor in
            do {
                try await store.snooze(current, until: date, hasTime: hasTime)
                refreshSnapshot()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func defaultSnoozeDate() -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    /// Re-point the snapshot at the store's fresh copy so completion, snooze,
    /// and due-date changes render live.
    private func refreshSnapshot() {
        if let fresh = (store.allReminders + store.completedReminders)
            .first(where: { $0.calendarItemIdentifier == current.calendarItemIdentifier }) {
            current = fresh
        }
    }

    private func toggleCompletion() {
        guard !togglingCompletion else { return }
        togglingCompletion = true
        Task { @MainActor in
            defer { togglingCompletion = false }
            do {
                let result = try await store.toggleCompletion(current)
                // Refresh the snapshot so completion state and date stay live.
                let fresh = (store.allReminders + store.completedReminders)
                    .first { $0.calendarItemIdentifier == current.calendarItemIdentifier }
                if let fresh { current = fresh } else { current.isCompleted = result.isCompleted }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Static MKMapView wrapper for the detail page's location map (macOS 13
/// predates SwiftUI's Map content API).
private struct LocationMapView: NSViewRepresentable {
    let coordinate: CLLocationCoordinate2D
    let title: String

    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.isRotateEnabled = false
        map.showsCompass = false
        map.pointOfInterestFilter = .excludingAll
        return map
    }

    func updateNSView(_ map: MKMapView, context: Context) {
        let annotation = MKPointAnnotation()
        annotation.coordinate = coordinate
        annotation.title = title
        map.removeAnnotations(map.annotations)
        map.addAnnotation(annotation)
        map.setRegion(MKCoordinateRegion(center: coordinate,
                                         latitudinalMeters: 1200,
                                         longitudinalMeters: 1200),
                      animated: false)
    }
}
