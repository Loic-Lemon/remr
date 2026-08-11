import AppKit
import EventKit
import Foundation

enum ReminderStoreError: LocalizedError {
    case noCalendar

    var errorDescription: String? {
        switch self {
        case .noCalendar: return "No Reminders list available"
        }
    }
}

/// Shadow copy of a deleted reminder, persisted to Application Support.
struct DeletedReminder: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var notes: String?
    var dueDate: Date?
    var isAllDay: Bool
    var priority: Int
    var calendarIdentifier: String?
    var location: DeletedLocation?
    var deletedAt: Date
}

struct DeletedLocation: Codable, Equatable {
    var title: String
    var latitude: Double
    var longitude: Double
    var radius: Double
}

@MainActor
final class ReminderStore: ObservableObject {
    enum AccessState { case notDetermined, authorized, denied }

    @Published private(set) var accessState: AccessState = .notDetermined
    @Published private(set) var overdue: [EKReminder] = []
    @Published private(set) var today: [EKReminder] = []
    /// All completed reminders, newest completion first (tab shows top 5).
    @Published private(set) var completedReminders: [EKReminder] = []
    @Published private(set) var allReminders: [EKReminder] = []   // search corpus
    /// Shadow copies of reminders deleted through remr, newest first.
    /// EventKit has no trash — `store.remove` is permanent — so remr snapshots
    /// deletions here to power the "Recently Deleted" tab.
    @Published private(set) var recentlyDeleted: [DeletedReminder] = []

    /// Single shared EventKit store instance (Apple requires one per process).
    private let store = EKEventStore()
    private var refreshTimer: Timer?
    private var eventStoreObserver: NSObjectProtocol?
    /// Bumped on every refresh() so a stale in-flight fetch (started before a
    /// newer refresh began) can't clobber fresher data when it lands.
    private var fetchGeneration = 0

    deinit {
        if let eventStoreObserver {
            NotificationCenter.default.removeObserver(eventStoreObserver)
        }
        refreshTimer?.invalidate()
    }

    // MARK: - Lifecycle

    func start() {
        loadDeleted()
        eventStoreObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        Task { await requestAccess() }
    }

    // MARK: - Access

    func requestAccess() async {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if #available(macOS 14.0, *) {
            switch status {
            case .authorized, .fullAccess:
                accessState = .authorized
                refresh()
                return
            case .writeOnly, .denied, .restricted:
                accessState = .denied
                return
            case .notDetermined:
                break
            @unknown default:
                accessState = .denied
                return
            }
        } else {
            switch status {
            case .authorized, .fullAccess:
                accessState = .authorized
                refresh()
                return
            case .writeOnly, .denied, .restricted:
                accessState = .denied
                return
            case .notDetermined:
                break
            @unknown default:
                accessState = .denied
                return
            }
        }

        let granted: Bool
        if #available(macOS 14.0, *) {
            do {
                try await store.requestFullAccessToReminders()
                granted = true
            } catch {
                granted = false
            }
        } else {
            granted = await withCheckedContinuation { cont in
                store.requestAccess(to: .reminder) { ok, _ in cont.resume(returning: ok) }
            }
        }

        let newStatus = EKEventStore.authorizationStatus(for: .reminder)
        if granted {
            let ok: Bool
            if #available(macOS 14.0, *) {
                ok = newStatus == .authorized || newStatus == .fullAccess
            } else {
                ok = newStatus == .authorized
            }
            if ok {
                accessState = .authorized
                refresh()
                return
            }
        }
        accessState = .denied
    }

    // MARK: - Fetching

    func refresh() {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        guard let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: startOfToday) else { return }

        // EventKit's date-range predicates misfile all-day reminders: an
        // all-day reminder due today comes back from the *overdue* range,
        // never the today range. Bucket by due date in Swift instead, so a
        // date-only "today" reminder lands under TODAY (like Reminders.app).
        let completedPred = store.predicateForCompletedReminders(withCompletionDateStarting: nil, ending: nil, calendars: nil)
        let allPred = store.predicateForReminders(in: nil)

        fetchGeneration += 1
        let gen = fetchGeneration
        Task { [weak self] in
            guard let self else { return }
            if let result = await self.fetchReminders(completedPred), gen == self.fetchGeneration {
                self.completedReminders = result.sorted { ($0.completionDate ?? .distantPast) > ($1.completionDate ?? .distantPast) }
            }
            if let result = await self.fetchReminders(allPred), gen == self.fetchGeneration {
                self.allReminders = result.sorted { lhs, rhs in
                    if Self.dueAscending(lhs, rhs, cal) { return true }
                    if Self.dueAscending(rhs, lhs, cal) { return false }
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                let (overdue, today) = Self.bucket(result, startOfToday: startOfToday,
                                                   startOfTomorrow: startOfTomorrow, calendar: cal)
                self.overdue = overdue
                self.today = today
            }
        }
    }

    /// Split incomplete reminders by due date: `[nil, startOfToday)` →
    /// overdue, `[startOfToday, startOfTomorrow)` → today; everything else
    /// (including nil due) is later. Done in Swift because EventKit's
    /// date-range predicates misfile all-day reminders — an all-day reminder
    /// due today is returned as overdue, never today.
    static func bucket(_ reminders: [EKReminder], startOfToday: Date, startOfTomorrow: Date, calendar: Calendar) -> (overdue: [EKReminder], today: [EKReminder]) {
        var overdue: [EKReminder] = []
        var today: [EKReminder] = []
        for reminder in reminders where !reminder.isCompleted {
            guard let due = reminder.dueDateComponents.flatMap({ calendar.date(from: $0) }) else { continue }
            if due < startOfToday {
                overdue.append(reminder)
            } else if due < startOfTomorrow {
                today.append(reminder)
            }
        }
        return (overdue.sorted { Self.dueAscending($0, $1, calendar) },
                today.sorted { Self.dueAscending($0, $1, calendar) })
    }

    /// nil return = fetch failed; previous array is kept, never crash.
    private func fetchReminders(_ predicate: NSPredicate) async -> [EKReminder]? {
        await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { reminders in
                cont.resume(returning: reminders)
            }
        }
    }

    private static func dueAscending(_ lhs: EKReminder, _ rhs: EKReminder, _ cal: Calendar) -> Bool {
        // NOTE: `cal.date(from: DateComponents())` returns year 1, not nil —
        // a bare `?? DateComponents()` fallback would sort nil-due first.
        let l = lhs.dueDateComponents.flatMap { cal.date(from: $0) }
        let r = rhs.dueDateComponents.flatMap { cal.date(from: $0) }
        switch (l, r) {
        case let (l?, r?): return l < r
        case (nil, _?): return false   // nil due dates sort last
        case (_?, nil): return true
        case (nil, nil): return false
        }
    }

    // MARK: - Mutations

    func deleteReminder(_ reminder: EKReminder) async {
        let snapshot = snapshotForDeletion(reminder)
        do {
            try store.remove(reminder, commit: true)
            if let snapshot {
                recentlyDeleted.insert(snapshot, at: 0)
                persistDeleted()
            }
            refresh()
        } catch {
            NSLog("remr: failed to delete: \(error)")
        }
    }

    /// Snapshot a reminder before permanent removal (taken while it still
    /// exists so every field is readable).
    func snapshotForDeletion(_ reminder: EKReminder) -> DeletedReminder? {
        guard let title = reminder.title, !title.isEmpty else { return nil }
        var location: DeletedLocation?
        if let structured = reminder.alarms?.first(where: { $0.structuredLocation != nil })?.structuredLocation,
           let coord = structured.geoLocation {
            location = DeletedLocation(title: structured.title ?? "",
                                       latitude: coord.coordinate.latitude,
                                       longitude: coord.coordinate.longitude,
                                       radius: structured.radius)
        }
        let comps = reminder.dueDateComponents
        return DeletedReminder(
            id: UUID(),
            title: title,
            notes: reminder.notes,
            dueDate: comps.flatMap { Calendar.current.date(from: $0) },
            isAllDay: comps != nil && comps?.hour == nil,
            priority: reminder.priority,
            calendarIdentifier: reminder.calendar?.calendarIdentifier,
            location: location,
            deletedAt: Date()
        )
    }

    /// Re-create a deleted reminder from its snapshot (best effort: the list
    /// may be gone, in which case it falls back to the default list).
    func restore(_ deleted: DeletedReminder) async {
        var location: EKStructuredLocation?
        if let loc = deleted.location {
            let structured = EKStructuredLocation()
            structured.title = loc.title
            structured.geoLocation = CLLocation(latitude: loc.latitude, longitude: loc.longitude)
            structured.radius = loc.radius
            location = structured
        }
        var dueComponents: DateComponents?
        if let due = deleted.dueDate {
            var comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: due)
            if deleted.isAllDay {
                comps.hour = nil
                comps.minute = nil
                comps.second = nil
            }
            dueComponents = comps
        }
        let calendar = deleted.calendarIdentifier.flatMap { store.calendar(withIdentifier: $0) }
        do {
            try await create(title: deleted.title, calendar: calendar, dueDate: dueComponents,
                             priority: deleted.priority, location: location, notes: deleted.notes)
            recentlyDeleted.removeAll { $0.id == deleted.id }
            persistDeleted()
        } catch {
            NSLog("remr: failed to restore '\(deleted.title)': \(error)")
        }
    }

    func deleteForever(_ deleted: DeletedReminder) {
        recentlyDeleted.removeAll { $0.id == deleted.id }
        persistDeleted()
    }

    // MARK: - Recently deleted persistence

    private var deletedFileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("remr", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("deleted.json")
    }

    private func loadDeleted() {
        guard let data = try? Data(contentsOf: deletedFileURL) else { return }
        if let items = try? JSONDecoder().decode([DeletedReminder].self, from: data) {
            recentlyDeleted = items.sorted { $0.deletedAt > $1.deletedAt }
        }
    }

    private func persistDeleted() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(recentlyDeleted) else { return }
        try? data.write(to: deletedFileURL, options: .atomic)
    }

    func toggleCompletion(_ reminder: EKReminder) async {
        reminder.isCompleted.toggle()
        if !reminder.isCompleted { reminder.completionDate = nil }
        do {
            try store.save(reminder, commit: true)
            refresh()
        } catch {
            NSLog("remr: failed to save completion toggle: \(error)")
        }
    }

    @discardableResult
    func create(title: String, calendar: EKCalendar?, dueDate: DateComponents?, priority: Int, location: EKStructuredLocation?, notes: String? = nil) async throws -> EKReminder {
        let reminder = EKReminder(eventStore: store)
        if let calendar {
            reminder.calendar = calendar
        } else if let defaultCal = store.defaultCalendarForNewReminders() {
            reminder.calendar = defaultCal
        } else if let first = reminderCalendars().first {
            reminder.calendar = first
        } else {
            throw ReminderStoreError.noCalendar
        }
        reminder.title = title
        reminder.notes = notes
        reminder.dueDateComponents = dueDate
        reminder.priority = priority
        if let location {
            let alarm = EKAlarm(relativeOffset: 0)
            alarm.structuredLocation = location
            alarm.proximity = .enter
            reminder.addAlarm(alarm)
        }
        try store.save(reminder, commit: true)
        refresh()
        return reminder
    }

    // MARK: - Lists

    func reminderCalendars() -> [EKCalendar] {
        store.calendars(for: .reminder)
    }

    /// Exact normalized match first; else shortest calendar title containing the token.
    func resolveList(token: String) -> (calendar: EKCalendar?, matchedTitle: String?) {
        let normalized = normalize(token)
        guard !normalized.isEmpty else { return (nil, nil) }
        let calendars = reminderCalendars()
        if let exact = calendars.first(where: { normalize($0.title) == normalized }) {
            return (exact, exact.title)
        }
        let containing = calendars.filter { normalize($0.title).contains(normalized) }
        if let shortest = containing.min(by: { $0.title.count < $1.title.count }) {
            return (shortest, shortest.title)
        }
        return (nil, nil)
    }

    private func normalize(_ s: String) -> String {
        s.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    // MARK: - Open in Reminders

    func openInReminders(_ reminder: EKReminder) {
        let id = reminder.calendarItemIdentifier
        // Reminders.app's declared scheme (hyphens, per its CFBundleURLTypes).
        if let url = URL(string: "x-apple-reminderkit://REMCDReminder/\(id)"),
           NSWorkspace.shared.open(url) {
            return
        }
        // Guaranteed minimum: launch Reminders.app.
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
