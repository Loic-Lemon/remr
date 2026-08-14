import AppKit
import EventKit
import SwiftUI

enum CalendarMode: String, CaseIterable, Identifiable {
    case month = "Month", week = "Week", day = "Day"
    var id: String { rawValue }
}

/// Snooze/clear callbacks handed to day surfaces for chip context menus.
struct CalendarActions {
    let onSnooze: (EKReminder, SnoozeChoice) -> Void
    let onCustomSnooze: (EKReminder) -> Void
    let onClearDue: (EKReminder) -> Void
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
                              actions: actions,
                              onSelectDay: selectDay,
                              onDrop: dropReminder,
                              onOpenDetail: onOpenDetail)
                case .week:
                    WeekGrid(calendar: calendar,
                             weekStart: CalendarGridMath.startOfWeek(for: anchor, calendar: calendar),
                             buckets: buckets,
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
            .padding(12)
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
    private var items: [EKReminder] {
        CalendarBuckets.visibleItems(all: store.allReminders,
                                     completed: store.completedReminders,
                                     showCompleted: showCompleted)
    }

    private var buckets: [Date: [EKReminder]] {
        CalendarBuckets.byDay(items, calendar: calendar)
    }

    private var actions: CalendarActions {
        CalendarActions(onSnooze: applySnooze,
                        onCustomSnooze: beginCustomSnooze,
                        onClearDue: clearDue)
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

/// Seven-column month grid modeled on ReminderEditView's MonthCalendar, but
/// cells show that day's due reminders instead of picking a date. Drag is
/// tracked manually (DragGesture + frame preferences): SwiftUI's onDrag
/// conflicts with the chips' right-click snooze menus on macOS.
private struct MonthGrid: View {
    let calendar: Calendar
    let month: Date
    let buckets: [Date: [EKReminder]]
    let actions: CalendarActions
    let onSelectDay: (Date) -> Void
    let onDrop: ([String], Date) -> Bool
    let onOpenDetail: (EKReminder) -> Void

    @State private var cellFrames: [Date: CGRect] = [:]
    @State private var chipFrames: [String: CGRect] = [:]
    @State private var dragging: (id: String, location: CGPoint)?

    private var weekdaySymbols: [String] {
        CalendarGridMath.weekdaySymbols(calendar: calendar)
    }
    private var leadingBlanks: Int {
        CalendarGridMath.leadingBlanks(for: month, calendar: calendar)
    }
    private var daysInMonth: Int {
        CalendarGridMath.daysInMonth(for: month, calendar: calendar)
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ZStack(alignment: .topLeading) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                          spacing: 4) {
                    ForEach(0..<(leadingBlanks + daysInMonth), id: \.self) { index in
                        if index < leadingBlanks {
                            Color.clear
                                .frame(height: 56)
                        } else {
                            dayCell(index - leadingBlanks + 1)
                        }
                    }
                }
                dragPreview
            }
            .coordinateSpace(name: calendarGridSpace)
        }
        .onPreferenceChange(ChipFramePreference.self) { chipFrames = $0 }
        .onPreferenceChange(CellFramePreference.self) { cellFrames = $0 }
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

    private func dayCell(_ day: Int) -> some View {
        let date = calendar.date(byAdding: .day, value: day - 1, to: month)!
        let items = buckets[date] ?? []
        let isToday = calendar.isDateInToday(date)
        let isDropTarget = dropHighlightDate == date
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(day)")
                .font(.caption2)
                .fontWeight(isToday ? .semibold : .regular)
                .foregroundStyle(isToday ? Color.accentColor : Color.primary)
            ForEach(items.prefix(3), id: \.calendarItemIdentifier) { reminder in
                ReminderChip(reminder: reminder,
                             color: chipColor(for: reminder),
                             actions: actions,
                             onDragChanged: dragChanged,
                             onDragEnded: dragEnded,
                             onOpenDetail: onOpenDetail)
            }
            if items.count > 3 {
                Text("+\(items.count - 3) more")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
        .padding(4)
        .background {
            if isToday || isDropTarget {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(isDropTarget ? 0.9 : 0.6),
                                  lineWidth: isDropTarget ? 2 : 1)
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
    let actions: CalendarActions
    let onSelectDay: (Date) -> Void
    let onDrop: ([String], Date) -> Bool
    let onOpenDetail: (EKReminder) -> Void

    @State private var cellFrames: [Date: CGRect] = [:]
    @State private var chipFrames: [String: CGRect] = [:]
    @State private var dragging: (id: String, location: CGPoint)?

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(CalendarGridMath.weekdaySymbols(calendar: calendar), id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ZStack(alignment: .topLeading) {
                ScrollView(.vertical) {
                    HStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { i in
                            dayColumn(i)
                        }
                    }
                }
                dragPreview
            }
            .coordinateSpace(name: calendarGridSpace)
        }
        .onPreferenceChange(ChipFramePreference.self) { chipFrames = $0 }
        .onPreferenceChange(CellFramePreference.self) { cellFrames = $0 }
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

    private func dayColumn(_ i: Int) -> some View {
        let date = calendar.date(byAdding: .day, value: i, to: weekStart)!
        let items = buckets[date] ?? []
        let isToday = calendar.isDateInToday(date)
        let isDropTarget = dropHighlightDate == date
        let symbol = calendar.veryShortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(symbol) \(calendar.component(.day, from: date))")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isToday ? Color.accentColor : Color.primary)
            ForEach(items.prefix(5), id: \.calendarItemIdentifier) { reminder in
                ReminderChip(reminder: reminder,
                             color: chipColor(for: reminder),
                             actions: actions,
                             onDragChanged: dragChanged,
                             onDragEnded: dragEnded,
                             onOpenDetail: onOpenDetail)
            }
            if items.count > 5 {
                Text("+\(items.count - 5) more")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .padding(4)
        .background {
            if isToday || isDropTarget {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(isDropTarget ? 0.9 : 0.6),
                                  lineWidth: isDropTarget ? 2 : 1)
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

    private var chipContent: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(reminder.title ?? "")
                .font(.caption2)
                .strikethrough(reminder.isCompleted)
                .foregroundStyle(reminder.isCompleted ? Color.secondary : Color.primary)
                .lineLimit(1)
        }
    }

    var body: some View {
        if reminder.isCompleted {
            chipContent
        } else {
            chipContent
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

/// The snooze context-menu items (presets + custom + clear), shared by chips
/// and day rows.
@ViewBuilder
private func snoozeMenuItems(for reminder: EKReminder, actions: CalendarActions) -> some View {
    Button { actions.onSnooze(reminder, .oneHour) } label: { Label("1 hour", systemImage: "clock") }
    Button { actions.onSnooze(reminder, .laterToday) } label: { Label("Later today", systemImage: "sun.max") }
    Button { actions.onSnooze(reminder, .tomorrowMorning) } label: { Label("Tomorrow morning", systemImage: "sunrise") }
    Button { actions.onSnooze(reminder, .tomorrowEvening) } label: { Label("Tomorrow evening", systemImage: "sunset") }
    Button { actions.onSnooze(reminder, .nextMonday) } label: { Label("Next Monday", systemImage: "calendar") }
    Button { actions.onSnooze(reminder, .thisWeekend) } label: { Label("This weekend", systemImage: "moon.zzz") }
    Divider()
    Button { actions.onCustomSnooze(reminder) } label: { Label("Pick date/time…", systemImage: "calendar.badge.clock") }
    Button { actions.onClearDue(reminder) } label: { Label("Clear due date", systemImage: "xmark.circle") }
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
