import AppKit
import EventKit
import SwiftUI

enum CalendarMode: String, CaseIterable, Identifiable {
    case month = "Month", week = "Week", day = "Day"
    var id: String { rawValue }
}

/// One today-to-due bar: the inclusive day range whose month/week cells
/// each render a segment, so consecutive cells read as a single bar.
private struct TimelineBar {
    let reminder: EKReminder
    let startDay: Date
    let endDay: Date
}

/// A compact escape hatch for crowded Gantt cells. It rotates the shared
/// chart to the first hidden lane instead of opening a disconnected list.
private struct TimelineOverflowButton: View {
    let bars: [TimelineBar]
    let onJump: () -> Void

    var body: some View {
        Button(action: onJump) {
            Label("\(bars.count) more", systemImage: "arrow.down")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Show these bars in the Gantt chart")
    }
}

/// Shared controls for rotating through the chart's global timeline lanes.
private struct GanttLaneControls: View {
    let start: Int
    let end: Int
    let total: Int
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Gantt bars")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(start)–\(end) of \(total)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 2) {
                laneButton(systemImage: "chevron.up",
                           help: "Show the previous Gantt bar",
                           enabled: canMoveUp,
                           action: onMoveUp)
                laneButton(systemImage: "chevron.down",
                           help: "Show the next Gantt bar",
                           enabled: canMoveDown,
                           action: onMoveDown)
            }
        }
        .padding(.leading, 9)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.05), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Gantt bars \(start) through \(end) of \(total)")
    }

    private func laneButton(systemImage: String,
                            help: String,
                            enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 24, height: 22)
                .background(Color.primary.opacity(enabled ? 0.09 : 0.035), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.primary : Color.secondary)
        .opacity(enabled ? 1 : 0.48)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Snooze/clear callbacks handed to day surfaces for chip context menus.
struct CalendarActions {
    let onSnooze: (EKReminder, SnoozeChoice) -> Void
    let onCustomSnooze: (EKReminder) -> Void
    let onClearDue: (EKReminder) -> Void
    let onMoveToList: (EKReminder, String?) -> Void
    let calendars: [EKCalendar]
}

/// Grid coordinate space shared by the month/week grids for drag geometry.
private let calendarGridSpace = "calendarGrid"

/// Chip frame per reminder id, in the grid's coordinate space.
private struct ChipFramePreference: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Day-cell frame per day, in the grid's coordinate space.
private struct CellFramePreference: PreferenceKey {
    static var defaultValue: [Date: CGRect] = [:]
    static func reduce(value: inout [Date: CGRect], nextValue: () -> [Date: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Centered popup calendar: reminders bucketed onto their due dates across
/// month, week, and day views. Chips are draggable to reschedule, right-click
/// snoozes, and "Show completed" reveals completed reminders struck through.
struct CalendarView: View {
    @EnvironmentObject private var store: ReminderStore
    @EnvironmentObject private var settings: SettingsStore
    let onCancel: () -> Void
    /// Double-clicking a reminder hands it to the main popover's detail page.
    var onOpenDetail: (EKReminder) -> Void = { _ in }
    private let calendar = Calendar.current
    @State private var mode: CalendarMode = .month
    /// Month start / week start / day for the currently shown period.
    @State private var anchor: Date = Date()
    /// Day the day view shows (also the day navigation lands on).
    @State private var selectedDay: Date = Date()
    /// Include completed reminders (struck through) on their due days.
    @State private var showCompleted = false
    /// Overlay today-to-due bars on the month and week grids.
    @State private var showTimeline = false
    @State private var showHelp = false
    @State private var snoozingReminder: EKReminder?
    @State private var snoozeShowingPicker = false
    @State private var panelError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.45)
            Group {
                switch mode {
                case .month:
                    MonthGrid(calendar: calendar,
                              month: CalendarGridMath.startOfMonth(for: anchor, calendar: calendar),
                              buckets: buckets,
                              timelineBars: timelineBars,
                              showTimeline: showTimeline,
                              actions: actions,
                              onSelectDay: selectDay,
                              onDrop: dropReminder,
                              onOpenDetail: onOpenDetail)
                case .week:
                    WeekGrid(calendar: calendar,
                             weekStart: CalendarGridMath.startOfWeek(for: anchor, calendar: calendar),
                             buckets: buckets,
                             timelineBars: timelineBars,
                             showTimeline: showTimeline,
                             actions: actions,
                             onSelectDay: selectDay,
                             onDrop: dropReminder,
                             onOpenDetail: onOpenDetail)
                case .day:
                    DayList(calendar: calendar,
                            day: CalendarGridMath.startOfDay(for: selectedDay, calendar: calendar),
                            items: CalendarBuckets.sorted(buckets[CalendarGridMath.startOfDay(for: selectedDay, calendar: calendar)] ?? [],
                                                          calendar: calendar),
                            actions: actions,
                            onOpenDetail: onOpenDetail)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider().opacity(0.45)
            footer
        }
        .liquidGlassPopup()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Calendar")
        .onExitCommand(perform: onCancel)
        .sheet(isPresented: $snoozeShowingPicker) {
            if let reminder = snoozingReminder {
                SnoozeDatePickerView(initialDate: dueDate(of: reminder) ?? defaultSnoozeDate(),
                                     initialHasTime: hasTime(of: reminder),
                                     onCancel: { snoozeShowingPicker = false },
                                     onSave: saveCustomSnooze)
            }
        }
    }

    /// Incomplete reminders only by default; "Show completed" adds completed.
    /// Hidden lists stay hidden here too, matching the main list, search,
    /// and mini calendar counts.
    private var items: [EKReminder] {
        CalendarBuckets.visibleItems(all: store.allReminders,
                                     completed: store.completedReminders,
                                     showCompleted: showCompleted)
            .filter { !settings.hiddenLists.contains($0.calendar?.calendarIdentifier ?? "") }
    }

    private var buckets: [Date: [EKReminder]] {
        CalendarBuckets.byDay(items, calendar: calendar)
    }

    /// Inclusive today-to-due ranges for dated reminders, backing the
    /// timeline segments in the month and week grids.
    private var timelineBars: [TimelineBar] {
        let today = calendar.startOfDay(for: Date())
        return timelineBarsSorted(items.compactMap { reminder in
            guard let due = reminder.dueDateComponents.flatMap({ calendar.date(from: $0) }) else { return nil }
            let day = calendar.startOfDay(for: due)
            return TimelineBar(reminder: reminder, startDay: min(today, day), endDay: max(today, day))
        })
    }

    private var actions: CalendarActions {
        CalendarActions(onSnooze: applySnooze,
                        onCustomSnooze: beginCustomSnooze,
                        onClearDue: clearDue,
                        onMoveToList: moveToList,
                        calendars: store.reminderCalendars())
    }

    // MARK: - Navigation

    private func selectDay(_ date: Date) {
        selectedDay = date
        anchor = date
        mode = .day
    }

    private func moveBy(_ delta: Int) {
        let unit: Calendar.Component
        switch mode {
        case .month: unit = .month
        case .week: unit = .weekOfYear
        case .day: unit = .day
        }
        if let newAnchor = calendar.date(byAdding: unit, value: delta, to: anchor) {
            anchor = newAnchor
        }
    }

    private func today() {
        anchor = Date()
        selectedDay = Date()
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { moveBy(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 22)
            }
            .buttonStyle(.plain)
            .help("Previous")
            Button { moveBy(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 22)
            }
            .buttonStyle(.plain)
            .help("Next")
            Button {
                today()
            } label: {
                Text("Today")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .liquidGlassChip()
            }
            .buttonStyle(.plain)
            Button {
                showHelp = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("What you can do with the calendar")
            .popover(isPresented: $showHelp, arrowEdge: .bottom) {
                CalendarHelpView()
            }
            Spacer()
            Text(title)
                .font(.title3.weight(.semibold))
            Spacer()
            Picker("View", selection: $mode) {
                ForEach(CalendarMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 180)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var title: String {
        switch mode {
        case .month:
            return anchor.formatted(.dateTime.month(.wide).year())
        case .week:
            let start = CalendarGridMath.startOfWeek(for: anchor, calendar: calendar)
            let end = calendar.date(byAdding: .day, value: 6, to: start)!
            let s = start.formatted(.dateTime.month(.abbreviated).day())
            let e = end.formatted(.dateTime.month(.abbreviated).day())
            let y = start.formatted(.dateTime.year())
            return "\(s) – \(e), \(y)"
        case .day:
            return selectedDay.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Toggle("Show completed", isOn: $showCompleted)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .font(.caption)
                .help("Include completed reminders (struck through) on their due days")
            Toggle("Show Gantt bars", isOn: $showTimeline)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .font(.caption)
                .help("Show Gantt bars from today to each due date across the month and week grids")
            Spacer()
            if let panelError {
                Text(panelError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Snooze

    private func applySnooze(_ reminder: EKReminder, _ choice: SnoozeChoice) {
        guard !reminder.isCompleted else { return }
        guard let result = SnoozeCalculator.date(for: choice, now: Date(), calendar: calendar) else {
            showError("Couldn't calculate snooze date")
            return
        }
        saveSnooze(reminder, until: result.date, hasTime: result.hasTime)
    }

    private func beginCustomSnooze(_ reminder: EKReminder) {
        guard !reminder.isCompleted else { return }
        snoozingReminder = reminder
        snoozeShowingPicker = true
    }

    private func clearDue(_ reminder: EKReminder) {
        saveSnooze(reminder, until: nil, hasTime: false)
    }

    private func moveToList(_ reminder: EKReminder, _ calendarIdentifier: String?) {
        Task { @MainActor in
            do {
                try await store.moveToList(reminder, calendarIdentifier: calendarIdentifier)
            } catch {
                showError(error.localizedDescription)
            }
        }
    }

    private func saveCustomSnooze(_ date: Date?, _ hasTime: Bool) {
        guard let reminder = snoozingReminder else { return }
        snoozeShowingPicker = false
        snoozingReminder = nil
        saveSnooze(reminder, until: date, hasTime: hasTime)
    }

    private func saveSnooze(_ reminder: EKReminder, until date: Date?, hasTime: Bool) {
        Task { @MainActor in
            do {
                try await store.snooze(reminder, until: date, hasTime: hasTime)
            } catch {
                showError(error.localizedDescription)
            }
        }
    }

    // MARK: - Reschedule (drag)

    private func dropReminder(_ identifiers: [String], on day: Date) -> Bool {
        guard let id = identifiers.first,
              let reminder = items.first(where: { $0.calendarItemIdentifier == id }),
              !reminder.isCompleted,
              let due = dueDate(of: reminder),
              !calendar.isDate(day, inSameDayAs: due) else { return false }
        Task { @MainActor in
            do {
                try await store.reschedule(reminder, to: day)
            } catch {
                showError(error.localizedDescription)
            }
        }
        return true
    }

    // MARK: - Helpers

    private func dueDate(of reminder: EKReminder) -> Date? {
        reminder.dueDateComponents.flatMap { calendar.date(from: $0) }
    }

    private func hasTime(of reminder: EKReminder) -> Bool {
        reminder.dueDateComponents?.hour != nil
    }

    private func defaultSnoozeDate() -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    private func showError(_ message: String) {
        panelError = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if panelError == message { panelError = nil }
        }
    }
}

/// Dot color for a reminder: completed → gray, past-due → red, else its first
/// tag's palette color (fallback accent), mirroring the main list's cues.
@MainActor
private func chipColor(for reminder: EKReminder) -> Color {
    if reminder.isCompleted { return .secondary }
    if let due = reminder.dueDateComponents.flatMap({ Calendar.current.date(from: $0) }),
       CalendarGridMath.isOverdue(due, now: Date(), calendar: .current) {
        return .red
    }
    let firstTag = NaturalLanguageParser.extractTags(from: (reminder.title ?? "") + " " + (reminder.notes ?? ""))
        .first?
        .lowercased()
    return firstTag.flatMap { TagStore.shared.color(for: $0) } ?? Color.accentColor
}

/// Timeline bars are globally ordered once, so every day renders a bar
/// in the same lane. This makes a multi-day reminder a real continuous
/// chart instead of a stack that jumps between cells.
private func timelineBarsSorted(_ bars: [TimelineBar]) -> [TimelineBar] {
    bars.sorted {
        if $0.startDay != $1.startDay { return $0.startDay < $1.startDay }
        if $0.endDay != $1.endDay { return $0.endDay < $1.endDay }
        return ($0.reminder.title ?? "") < ($1.reminder.title ?? "")
    }
}

/// The calendar renders a bar segment in every covered cell. Global ordering
/// keeps each segment on the same lane across consecutive days.
/// Compact week strip: the seven days of `date`'s week. The `date` day fills
/// accent, today gets an accent outline plus a "TODAY" label, and days in
/// `reminderDays` show a dot. Shared by the detail page and the popover's
/// bottom calendar.
struct MiniWeekView: View {
    let calendar: Calendar
    let date: Date
    let today: Date
    /// startOfDay → incomplete reminders due that day (red badge).
    var activeCounts: [Date: Int] = [:]
    /// startOfDay → completed reminders due that day (gray badge).
    var completedCounts: [Date: Int] = [:]
    /// True (default) wraps the strip in its own inset card; false lets the
    /// parent surface (e.g. the popover's bottom glass band) carry it.
    var inset: Bool = true

    var body: some View {
        Group {
            if inset {
                stripContent
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
            } else {
                stripContent
            }
        }
    }

    /// Compact week strip: faint day names above each day, the date number
    /// (the anchor day filled accent, today outlined) with the active (red)
    /// and completed (gray) counts to its right, and the week number of the
    /// year at the far left. One HStack, so all columns stay aligned.
    private var stripContent: some View {
        let weekStart = CalendarGridMath.startOfWeek(for: date, calendar: calendar)
        let weekNumber = calendar.component(.weekOfYear, from: date)
        return HStack(spacing: 0) {
            Text("W\(weekNumber)")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
            ForEach(0..<7, id: \.self) { i in
                let day = calendar.date(byAdding: .day, value: i, to: weekStart)!
                let dayStart = calendar.startOfDay(for: day)
                let isDue = calendar.isDate(day, inSameDayAs: date)
                let isToday = calendar.isDate(day, inSameDayAs: today)
                let active = activeCounts[dayStart] ?? 0
                let completed = completedCounts[dayStart] ?? 0
                // A dedicated blue for today's markers: the user accent can be
                // anything, but this one is readable on the glass in both
                // appearances.
                let markerBlue = Color.blue
                VStack(spacing: 2) {
                    Text(calendar.shortWeekdaySymbols[calendar.component(.weekday, from: day) - 1])
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    // The date number: always centered in the column.
                    Text("\(calendar.component(.day, from: day))")
                        .font(.system(size: 12.5, weight: isDue ? .semibold : .regular, design: .rounded))
                        .tracking(0.3)
                        .foregroundStyle((isDue || isToday) ? markerBlue : Color.primary)
                        .frame(width: 24, height: 18)
                        .background {
                            if !isDue && isToday {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(markerBlue.opacity(0.55), lineWidth: 1.2)
                            }
                        }
                    // Marker row, in the same 24pt slot as the number:
                    // one count centered, both sharing red-left/gray-right,
                    // the today dot alone when the day has no counts.
                    HStack(spacing: 3) {
                        if active > 0 && completed > 0 {
                            Text("\(active)")
                                .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .tracking(0.4)
                                .foregroundStyle(.red)
                            Spacer(minLength: 0)
                            Text("\(completed)")
                                .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .tracking(0.4)
                                .foregroundStyle(.gray)
                        } else if active > 0 {
                            Spacer(minLength: 0)
                            Text("\(active)")
                                .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .tracking(0.4)
                                .foregroundStyle(.red)
                            Spacer(minLength: 0)
                        } else if completed > 0 {
                            Spacer(minLength: 0)
                            Text("\(completed)")
                                .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .tracking(0.4)
                                .foregroundStyle(.gray)
                            Spacer(minLength: 0)
                        } else if isDue {
                            Spacer(minLength: 0)
                            Circle()
                                .fill(markerBlue)
                                .frame(width: 3, height: 3)
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(width: 24, height: 9)
                }
                .frame(maxWidth: .infinity)
            }
            Text(monthLabel)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    private var monthLabel: String {
        calendar.shortMonthSymbols[calendar.component(.month, from: date) - 1].uppercased()
    }
}

/// Seven-column month grid modeled on ReminderEditView's MonthCalendar, but
/// cells show that day's due reminders instead of picking a date. Drag is
/// tracked manually (DragGesture + frame preferences): SwiftUI's onDrag
/// conflicts with the chips' right-click snooze menus on macOS.
private struct MonthGrid: View {
    let calendar: Calendar
    let month: Date
    let buckets: [Date: [EKReminder]]
    let timelineBars: [TimelineBar]
    let showTimeline: Bool
    let actions: CalendarActions
    let onSelectDay: (Date) -> Void
    let onDrop: ([String], Date) -> Bool
    let onOpenDetail: (EKReminder) -> Void

    @State private var cellFrames: [Date: CGRect] = [:]
    @State private var chipFrames: [String: CGRect] = [:]
    @State private var dragging: (id: String, location: CGPoint)?
    @State private var laneOffset = 0

    private var weekdaySymbols: [String] {
        CalendarGridMath.weekdaySymbols(calendar: calendar)
    }
    private var leadingBlanks: Int {
        CalendarGridMath.leadingBlanks(for: month, calendar: calendar)
    }
    private var daysInMonth: Int {
        CalendarGridMath.daysInMonth(for: month, calendar: calendar)
    }

    private var rowCount: Int {
        Int(ceil(Double(leadingBlanks + daysInMonth) / 7.0))
    }

    var body: some View {
        GeometryReader { proxy in
            let headerHeight: CGFloat = showTimeline ? 58 : 30
            let cellHeight = max(104, (proxy.size.height - headerHeight - CGFloat(max(0, rowCount - 1)) * 4 - CGFloat(rowCount) * 8) / CGFloat(rowCount))
            let laneCapacity = max(1, Int((cellHeight - 28) / 20))
            let visibleOffset = clampedLaneOffset(capacity: laneCapacity)
            VStack(spacing: 8) {
                if showTimeline && !timelineBars.isEmpty {
                    laneControls(capacity: laneCapacity, offset: visibleOffset)
                }
                HStack(spacing: 4) {
                    ForEach(weekdaySymbols, id: \.self) { symbol in
                        Text(symbol)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                ZStack(alignment: .topLeading) {
                    ScrollView(.vertical) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                                  spacing: showTimeline ? 0 : 4) {
                            ForEach(0..<(leadingBlanks + daysInMonth), id: \.self) { index in
                                if index < leadingBlanks {
                                    Color.clear
                                        .frame(height: cellHeight)
                                } else {
                                    dayCell(index - leadingBlanks + 1,
                                            height: cellHeight,
                                            laneOffset: visibleOffset)
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    dragPreview
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .coordinateSpace(name: calendarGridSpace)
            }
        }
        .onPreferenceChange(ChipFramePreference.self) { chipFrames = $0 }
        .onPreferenceChange(CellFramePreference.self) { cellFrames = $0 }
        .onChange(of: month) { _ in laneOffset = 0 }
        .onChange(of: showTimeline) { _ in laneOffset = 0 }
    }

    private var dropHighlightDate: Date? {
        guard let dragging else { return nil }
        return cellFrames.first { $0.value.contains(dragging.location) }?.key
    }

    private var draggingReminder: EKReminder? {
        guard let id = dragging?.id else { return nil }
        return buckets.values.flatMap { $0 }.first { $0.calendarItemIdentifier == id }
    }

    @ViewBuilder
    private var dragPreview: some View {
        if let dragging, let reminder = draggingReminder {
            HStack(spacing: 4) {
                Circle()
                    .fill(chipColor(for: reminder))
                    .frame(width: 5, height: 5)
                Text(reminder.title ?? "")
                    .font(.caption2)
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .liquidGlassChip()
            .position(x: dragging.location.x + 14, y: dragging.location.y + 10)
            .allowsHitTesting(false)
        }
    }

    private func dragChanged(_ id: String, _ local: CGPoint) {
        guard let frame = chipFrames[id] else { return }
        dragging = (id, CGPoint(x: frame.minX + local.x, y: frame.minY + local.y))
    }

    private func dragEnded(_ id: String, _ local: CGPoint) {
        guard let current = dragging, current.id == id else { dragging = nil; return }
        let gridPoint = chipFrames[id].map { CGPoint(x: $0.minX + local.x, y: $0.minY + local.y) }
            ?? current.location
        dragging = nil
        if let target = cellFrames.first(where: { $0.value.contains(gridPoint) })?.key {
            _ = onDrop([id], target)
        }
    }

    private func clampedLaneOffset(capacity: Int) -> Int {
        min(max(0, laneOffset), max(0, timelineBars.count - capacity))
    }

    private func laneControls(capacity: Int, offset: Int) -> some View {
        GanttLaneControls(start: offset + 1,
                          end: min(timelineBars.count, offset + capacity),
                          total: timelineBars.count,
                          canMoveUp: offset > 0,
                          canMoveDown: offset + capacity < timelineBars.count,
                          onMoveUp: { moveLane(by: -1, capacity: capacity) },
                          onMoveDown: { moveLane(by: 1, capacity: capacity) })
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func moveLane(by delta: Int, capacity: Int) {
        withAnimation(.easeInOut(duration: 0.18)) {
            laneOffset = min(max(0, laneOffset + delta), max(0, timelineBars.count - capacity))
        }
    }

    private func moveLane(to offset: Int, capacity: Int) {
        withAnimation(.easeInOut(duration: 0.18)) {
            laneOffset = min(max(0, offset), max(0, timelineBars.count - capacity))
        }
    }

    /// Chips for the day, or full-bleed timeline segments when the overlay
    /// is on (extracted so the cell body stays type-checkable).
    @ViewBuilder
    private func dayItems(date: Date, items: [EKReminder], height: CGFloat, laneOffset: Int) -> some View {
        if showTimeline {
            let maxBars = max(1, Int((height - 28) / 20))
            let activeBars = timelineBars.filter { $0.startDay <= date && date <= $0.endDay }
            let visibleBars = Array(timelineBars.dropFirst(laneOffset).prefix(maxBars))
            // Keep the same global lane window across every day. Crowded cells
            // can jump the whole chart to their first hidden lane.
            ForEach(visibleBars, id: \.reminder.calendarItemIdentifier) { bar in
                if bar.startDay <= date && date <= bar.endDay {
                    ReminderChip(reminder: bar.reminder,
                                 color: chipColor(for: bar.reminder),
                                 actions: actions,
                                 onDragChanged: dragChanged,
                                 onDragEnded: dragEnded,
                                 onOpenDetail: onOpenDetail,
                                 showTitle: bar.startDay == date,
                                 spanEdge: (start: bar.startDay == date, end: bar.endDay == date))
                } else {
                    Color.clear.frame(height: 18)
                }
            }
            let visibleIDs = Set(visibleBars.map(\.reminder.calendarItemIdentifier))
            let overflow = activeBars.filter { !visibleIDs.contains($0.reminder.calendarItemIdentifier) }
            if !overflow.isEmpty,
               let firstHidden = overflow.first,
               let firstHiddenIndex = timelineBars.firstIndex(where: { $0.reminder.calendarItemIdentifier == firstHidden.reminder.calendarItemIdentifier }) {
                TimelineOverflowButton(bars: overflow) {
                    moveLane(to: firstHiddenIndex, capacity: maxBars)
                }
            }
        } else {
            ForEach(items.prefix(4), id: \.calendarItemIdentifier) { reminder in
                ReminderChip(reminder: reminder, color: chipColor(for: reminder), actions: actions,
                             onDragChanged: dragChanged, onDragEnded: dragEnded, onOpenDetail: onOpenDetail)
            }
            if items.count > 4 { Text("+\(items.count - 4) more").font(.caption2).foregroundStyle(.secondary) }
        }
    }

    private func dayCell(_ day: Int, height: CGFloat, laneOffset: Int) -> some View {
        let date = calendar.date(byAdding: .day, value: day - 1, to: month)!
        let items = buckets[date] ?? []
        let isToday = calendar.isDateInToday(date)
        let isDropTarget = dropHighlightDate == date
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(day)")
                .font(.caption2)
                .fontWeight(isToday ? .semibold : .regular)
                .foregroundStyle(isToday ? Color.accentColor : Color.primary)
            dayItems(date: date, items: items, height: height, laneOffset: laneOffset)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .padding(4)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(isToday ? 0.055 : 0.025))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
                }
                .overlay {
                    if isToday || isDropTarget {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(isDropTarget ? 0.9 : 0.65),
                                          lineWidth: isDropTarget ? 2 : 1.2)
                    }
                }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectDay(date)
        }
        .background(GeometryReader { geo in
            Color.clear.preference(key: CellFramePreference.self,
                                   value: [date: geo.frame(in: .named(calendarGridSpace))])
        })
    }
}

/// Seven equal day columns for the week view; the whole grid scrolls
/// vertically, chips truncate, and no column scrolls on its own.
private struct WeekGrid: View {
    let calendar: Calendar
    let weekStart: Date
    let buckets: [Date: [EKReminder]]
    let timelineBars: [TimelineBar]
    let showTimeline: Bool
    let actions: CalendarActions
    let onSelectDay: (Date) -> Void
    let onDrop: ([String], Date) -> Bool
    let onOpenDetail: (EKReminder) -> Void

    @State private var cellFrames: [Date: CGRect] = [:]
    @State private var chipFrames: [String: CGRect] = [:]
    @State private var dragging: (id: String, location: CGPoint)?
    @State private var laneOffset = 0

    var body: some View {
        GeometryReader { proxy in
            let headerHeight: CGFloat = showTimeline ? 58 : 30
            let columnHeight = max(300, proxy.size.height - headerHeight)
            let laneCapacity = max(1, Int((columnHeight - 28) / 20))
            let visibleOffset = clampedLaneOffset(capacity: laneCapacity)
            VStack(spacing: 8) {
                if showTimeline && !timelineBars.isEmpty {
                    laneControls(capacity: laneCapacity, offset: visibleOffset)
                }
                HStack(spacing: 4) {
                    ForEach(CalendarGridMath.weekdaySymbols(calendar: calendar), id: \.self) { symbol in
                        Text(symbol)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                ZStack(alignment: .topLeading) {
                    ScrollView(.vertical) {
                        HStack(spacing: showTimeline ? 0 : 4) {
                            ForEach(0..<7, id: \.self) { i in
                                dayColumn(i, height: columnHeight, laneOffset: visibleOffset)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    dragPreview
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .coordinateSpace(name: calendarGridSpace)
            }
        }
        .onPreferenceChange(ChipFramePreference.self) { chipFrames = $0 }
        .onPreferenceChange(CellFramePreference.self) { cellFrames = $0 }
        .onChange(of: weekStart) { _ in laneOffset = 0 }
        .onChange(of: showTimeline) { _ in laneOffset = 0 }
    }

    private var dropHighlightDate: Date? {
        guard let dragging else { return nil }
        return cellFrames.first { $0.value.contains(dragging.location) }?.key
    }

    private var draggingReminder: EKReminder? {
        guard let id = dragging?.id else { return nil }
        return buckets.values.flatMap { $0 }.first { $0.calendarItemIdentifier == id }
    }

    @ViewBuilder
    private var dragPreview: some View {
        if let dragging, let reminder = draggingReminder {
            HStack(spacing: 4) {
                Circle()
                    .fill(chipColor(for: reminder))
                    .frame(width: 5, height: 5)
                Text(reminder.title ?? "")
                    .font(.caption2)
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .liquidGlassChip()
            .position(x: dragging.location.x + 14, y: dragging.location.y + 10)
            .allowsHitTesting(false)
        }
    }

    private func dragChanged(_ id: String, _ local: CGPoint) {
        guard let frame = chipFrames[id] else { return }
        dragging = (id, CGPoint(x: frame.minX + local.x, y: frame.minY + local.y))
    }

    private func dragEnded(_ id: String, _ local: CGPoint) {
        guard let current = dragging, current.id == id else { dragging = nil; return }
        let gridPoint = chipFrames[id].map { CGPoint(x: $0.minX + local.x, y: $0.minY + local.y) }
            ?? current.location
        dragging = nil
        if let target = cellFrames.first(where: { $0.value.contains(gridPoint) })?.key {
            _ = onDrop([id], target)
        }
    }

    private func clampedLaneOffset(capacity: Int) -> Int {
        min(max(0, laneOffset), max(0, timelineBars.count - capacity))
    }

    private func laneControls(capacity: Int, offset: Int) -> some View {
        GanttLaneControls(start: offset + 1,
                          end: min(timelineBars.count, offset + capacity),
                          total: timelineBars.count,
                          canMoveUp: offset > 0,
                          canMoveDown: offset + capacity < timelineBars.count,
                          onMoveUp: { moveLane(by: -1, capacity: capacity) },
                          onMoveDown: { moveLane(by: 1, capacity: capacity) })
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func moveLane(by delta: Int, capacity: Int) {
        withAnimation(.easeInOut(duration: 0.18)) {
            laneOffset = min(max(0, laneOffset + delta), max(0, timelineBars.count - capacity))
        }
    }

    private func moveLane(to offset: Int, capacity: Int) {
        withAnimation(.easeInOut(duration: 0.18)) {
            laneOffset = min(max(0, offset), max(0, timelineBars.count - capacity))
        }
    }

    /// Chips for the column, or full-bleed timeline segments when the
    /// overlay is on (extracted so the column body stays type-checkable).
    @ViewBuilder
    private func columnItems(date: Date, items: [EKReminder], height: CGFloat, laneOffset: Int) -> some View {
        if showTimeline {
            let maxBars = max(1, Int((height - 28) / 20))
            let activeBars = timelineBars.filter { $0.startDay <= date && date <= $0.endDay }
            let visibleBars = Array(timelineBars.dropFirst(laneOffset).prefix(maxBars))
            ForEach(visibleBars, id: \.reminder.calendarItemIdentifier) { bar in
                if bar.startDay <= date && date <= bar.endDay {
                    ReminderChip(reminder: bar.reminder,
                                 color: chipColor(for: bar.reminder),
                                 actions: actions,
                                 onDragChanged: dragChanged,
                                 onDragEnded: dragEnded,
                                 onOpenDetail: onOpenDetail,
                                 showTitle: bar.startDay == date,
                                 spanEdge: (start: bar.startDay == date, end: bar.endDay == date))
                } else {
                    Color.clear.frame(height: 18)
                }
            }
            let visibleIDs = Set(visibleBars.map(\.reminder.calendarItemIdentifier))
            let overflow = activeBars.filter { !visibleIDs.contains($0.reminder.calendarItemIdentifier) }
            if !overflow.isEmpty,
               let firstHidden = overflow.first,
               let firstHiddenIndex = timelineBars.firstIndex(where: { $0.reminder.calendarItemIdentifier == firstHidden.reminder.calendarItemIdentifier }) {
                TimelineOverflowButton(bars: overflow) {
                    moveLane(to: firstHiddenIndex, capacity: maxBars)
                }
            }
        } else {
            ForEach(items.prefix(5), id: \.calendarItemIdentifier) { reminder in
                ReminderChip(reminder: reminder, color: chipColor(for: reminder), actions: actions,
                             onDragChanged: dragChanged, onDragEnded: dragEnded, onOpenDetail: onOpenDetail)
            }
            if items.count > 5 { Text("+\(items.count - 5) more").font(.caption2).foregroundStyle(.secondary) }
        }
    }

    private func dayColumn(_ i: Int, height: CGFloat, laneOffset: Int) -> some View {
        let date = calendar.date(byAdding: .day, value: i, to: weekStart)!
        let items = buckets[date] ?? []
        let isToday = calendar.isDateInToday(date)
        let isDropTarget = dropHighlightDate == date
        let symbol = calendar.veryShortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(symbol) \(calendar.component(.day, from: date))")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isToday ? Color.accentColor : Color.primary)
            columnItems(date: date, items: items, height: height, laneOffset: laneOffset)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .padding(4)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(isToday ? 0.055 : 0.025))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
                }
                .overlay {
                    if isToday || isDropTarget {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(isDropTarget ? 0.9 : 0.65),
                                          lineWidth: isDropTarget ? 2 : 1.2)
                    }
                }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectDay(date)
        }
        .background(GeometryReader { geo in
            Color.clear.preference(key: CellFramePreference.self,
                                   value: [date: geo.frame(in: .named(calendarGridSpace))])
        })
    }
}

/// Flat reminder rows for the day view; the panel's own glass is the surface.
private struct DayList: View {
    let calendar: Calendar
    let day: Date
    let items: [EKReminder]
    let actions: CalendarActions
    let onOpenDetail: (EKReminder) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if items.isEmpty {
                    Text("No reminders due")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                } else {
                    ForEach(items, id: \.calendarItemIdentifier) { reminder in
                        row(for: reminder)
                        Divider().padding(.leading, 8)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(for reminder: EKReminder) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(chipColor(for: reminder))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(reminder.title ?? "")
                    .font(.callout)
                    .strikethrough(reminder.isCompleted)
                    .foregroundStyle(reminder.isCompleted ? Color.secondary : Color.primary)
                Text(sublabel(for: reminder))
                    .font(.caption)
                    .foregroundStyle(sublabelColor(for: reminder))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onOpenDetail(reminder)
        }
        .contextMenu {
            if !reminder.isCompleted {
                snoozeMenuItems(for: reminder, actions: actions)
            }
        }
    }

    private func sublabel(for reminder: EKReminder) -> String {
        if reminder.isCompleted {
            if let completion = reminder.completionDate {
                return completion.formatted(date: .omitted, time: .shortened)
            }
            return "Completed"
        }
        return timeLabel(for: reminder)
    }

    private func sublabelColor(for reminder: EKReminder) -> Color {
        if reminder.isCompleted { return .secondary }
        if let due = reminder.dueDateComponents.flatMap({ calendar.date(from: $0) }),
           CalendarGridMath.isOverdue(due, now: Date(), calendar: calendar) {
            return .red
        }
        return .secondary
    }

    private func timeLabel(for reminder: EKReminder) -> String {
        guard let components = reminder.dueDateComponents else { return "" }
        if components.hour == nil { return "All day" }
        guard let date = calendar.date(from: components) else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// Dot + truncated title. Right-click snoozes; left-drag reschedules (the
/// gesture reports points in the chip's local space; the grid maps them via
/// the reported frame).
private struct ReminderChip: View {
    let reminder: EKReminder
    let color: Color
    let actions: CalendarActions
    let onDragChanged: (String, CGPoint) -> Void
    let onDragEnded: (String, CGPoint) -> Void
    let onOpenDetail: (EKReminder) -> Void
    var showTitle: Bool = true
    /// Timeline segment edges: when set, the chip renders full-bleed with
    /// square sides where the span continues into the adjacent cell, so
    /// consecutive cells read as one bar. Nil renders the classic chip.
    /// (`var` so the memberwise init keeps it as a defaulted parameter.)
    var spanEdge: (start: Bool, end: Bool)? = nil

    private var chipContent: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            if showTitle {
                Text(reminder.title ?? "")
                    .font(.caption2)
                    .strikethrough(reminder.isCompleted)
                    .foregroundStyle(reminder.isCompleted ? Color.secondary : Color.primary)
                    .lineLimit(1)
            }
        }
    }

    var body: some View {
        if reminder.isCompleted {
            chipContent
        } else {
            chipContent
                .frame(maxWidth: spanEdge == nil ? nil : .infinity,
                       minHeight: spanEdge == nil ? nil : 18,
                       alignment: .leading)
                .padding(.horizontal, spanEdge == nil ? 0 : -4)
                .zIndex(spanEdge == nil ? 0 : 1)
                .background {
                    if let spanEdge {
                        UnevenRoundedRectangle(
                            topLeadingRadius: spanEdge.start ? 6 : 0,
                            bottomLeadingRadius: spanEdge.start ? 6 : 0,
                            bottomTrailingRadius: spanEdge.end ? 6 : 0,
                            topTrailingRadius: spanEdge.end ? 6 : 0,
                            style: .continuous)
                            .fill(color.opacity(0.22))
                    }
                }
                .background(GeometryReader { geo in
                    Color.clear.preference(key: ChipFramePreference.self,
                                           value: [reminder.calendarItemIdentifier: geo.frame(in: .named(calendarGridSpace))])
                })
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    onOpenDetail(reminder)
                }
                .contextMenu {
                    snoozeMenuItems(for: reminder, actions: actions)
                }
                .gesture(
                    DragGesture(minimumDistance: 3)
                        .onChanged { value in
                            onDragChanged(reminder.calendarItemIdentifier, value.location)
                        }
                        .onEnded { value in
                            onDragEnded(reminder.calendarItemIdentifier, value.location)
                        }
                )
        }
    }
}

/// The snooze context-menu items (presets + custom + clear), shared by chips,
/// day rows, and the detail page's overflow menu.
@ViewBuilder
func snoozeMenuItems(for reminder: EKReminder, actions: CalendarActions) -> some View {
    Button { actions.onSnooze(reminder, .oneHour) } label: { Label("1 hour", systemImage: "clock") }
    Button { actions.onSnooze(reminder, .laterToday) } label: { Label("Later today", systemImage: "sun.max") }
    Button { actions.onSnooze(reminder, .tomorrowMorning) } label: { Label("Tomorrow morning", systemImage: "sunrise") }
    Button { actions.onSnooze(reminder, .tomorrowEvening) } label: { Label("Tomorrow evening", systemImage: "sunset") }
    Button { actions.onSnooze(reminder, .nextMonday) } label: { Label("Next Monday", systemImage: "calendar") }
    Button { actions.onSnooze(reminder, .thisWeekend) } label: { Label("This weekend", systemImage: "moon.zzz") }
    Divider()
    Button { actions.onCustomSnooze(reminder) } label: { Label("Pick date/time…", systemImage: "calendar.badge.clock") }
    Button { actions.onClearDue(reminder) } label: { Label("Clear due date", systemImage: "xmark.circle") }
    Divider()
    Menu("Move to List") {
        Button("Default list") { actions.onMoveToList(reminder, nil) }
        Divider()
        ForEach(actions.calendars, id: \.calendarIdentifier) { calendar in
            Button(calendar.title) { actions.onMoveToList(reminder, calendar.calendarIdentifier) }
        }
    }
}


/// The (i) popover listing what the calendar can do.
private struct CalendarHelpView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Calendar")
                .font(.headline)
            helpRow("Click a day to open its Day view")
            helpRow("Drag a reminder chip to another day to move it (time is kept)")
            helpRow("Right-click a reminder to snooze or clear its due date")
            helpRow("Red dot = overdue · coloured dot = the reminder's tag")
            helpRow("“Show completed” adds finished reminders, struck through")
            helpRow("Show Gantt bars stretch from today to each due date (red = overdue)")
            helpRow("Esc closes · ⌥⌘C opens from anywhere")
        }
        .padding(12)
        .frame(width: 250, alignment: .leading)
        .liquidGlassPane(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .liquidGlassGrouping()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("What the calendar can do")
    }

    private func helpRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 4, height: 4)
                .padding(.top, 5)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
