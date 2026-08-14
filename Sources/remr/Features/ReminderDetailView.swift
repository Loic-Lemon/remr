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

    @State private var current: EKReminder
    @State private var togglingCompletion = false
    @State private var errorMessage: String?

    init(reminder: EKReminder,
         onClose: @escaping () -> Void,
         onEdit: @escaping (EKReminder) -> Void) {
        self.onClose = onClose
        self.onEdit = onEdit
        _current = State(initialValue: reminder)
    }

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    titleBlock
                    if let notes = current.notes, !notes.isEmpty {
                        notesBlock(notes)
                    }
                    if !tags.isEmpty {
                        tagsBlock
                    }
                    infoCard
                    if let location = structuredLocation {
                        locationCard(location)
                    }
                }
                .padding(14)
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
            Divider()
                .padding(.horizontal, 12)
                .padding(.top, 6)
            footer
        }
        .liquidGlassPane(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Reminder details")
        .onExitCommand(perform: onClose)
    }

    // MARK: - Blocks

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                onClose()
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            Spacer()
            Text("Reminder")
                .font(.headline)
            Spacer()
            // Balanced trailing spacer keeps the title centered.
            Color.clear
                .frame(width: 62, height: 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(current.title ?? "")
                .font(.title3.weight(.semibold))
                .strikethrough(isCompleted)
                .foregroundStyle(isCompleted ? Color.secondary : Color.primary)
                .textSelection(.enabled)
            if isCompleted {
                Text(completionLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let due = dueDate {
                HStack(spacing: 6) {
                    Image(systemName: isOverdue ? "exclamationmark.circle.fill" : "calendar")
                        .font(.caption)
                        .foregroundStyle(isOverdue ? Color.red : Color.secondary)
                    Text(isAllDay
                         ? due.formatted(date: .abbreviated, time: .omitted) + " · All day"
                         : due.formatted(date: .abbreviated, time: .shortened))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(isOverdue ? Color.red : Color.primary)
                }
            }
        }
    }

    private func notesBlock(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel("Description")
            Text(notes)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
        }
    }

    private var tagsBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel("Tags")
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .liquidGlassChip(tint: tagStore.color(for: tag), filled: true)
                }
            }
        }
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Details")
            infoRow(systemImage: "list.bullet",
                    label: "List",
                    value: current.calendar?.title ?? "Default",
                    dotColor: calendarColor)
            if priorityLabel != nil {
                infoRow(systemImage: "flag", label: "Priority", value: priorityLabel!)
            }
            if let recurrence = recurrenceSummary {
                infoRow(systemImage: "repeat", label: "Repeats", value: recurrence)
            }
            infoRow(systemImage: "calendar.badge.plus",
                    label: "Created",
                    value: (current.creationDate ?? Date()).formatted(date: .abbreviated, time: .shortened))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func locationCard(_ location: EKStructuredLocation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Location")
            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(location.title ?? "Location")
                    .font(.callout.weight(.medium))
            }
            if let coordinate = coordinate {
                LocationMapView(coordinate: coordinate, title: location.title ?? "")
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                    )
            }
            Text("Notifies when you arrive")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

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

    private var isAllDay: Bool {
        current.dueDateComponents?.hour == nil
    }

    private var isOverdue: Bool {
        guard let due = dueDate, !isCompleted else { return false }
        return CalendarGridMath.isOverdue(due, now: Date(), calendar: calendar)
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

    // MARK: - Actions

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

    private func infoRow(systemImage: String, label: String, value: String, dotColor: Color? = nil) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let dotColor {
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
            }
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
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
