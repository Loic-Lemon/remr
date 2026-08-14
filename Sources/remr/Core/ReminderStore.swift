import AppKit
import EventKit
import Foundation

enum ReminderStoreError: LocalizedError {
    case noCalendar
    case unresolvedLocation(String)
    case reminderNotFound
    case tagRemovalWouldEmptyTitle(String)

    var errorDescription: String? {
        switch self {
        case .noCalendar: return "No Reminders list available"
        case .unresolvedLocation(let phrase): return "Location “\(phrase)” has not been resolved"
        case .reminderNotFound: return "Reminder no longer exists"
        case .tagRemovalWouldEmptyTitle(let tag):
            return "Can't remove #\(tag) because it is the reminder's only title"
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
    var isCompleted: Bool = false
    var completionDate: Date? = nil

    private enum CodingKeys: String, CodingKey {
        case id, title, notes, dueDate, isAllDay, priority, calendarIdentifier
        case location, deletedAt, isCompleted, completionDate
    }

    init(id: UUID,
         title: String,
         notes: String?,
         dueDate: Date?,
         isAllDay: Bool,
         priority: Int,
         calendarIdentifier: String?,
         location: DeletedLocation?,
         deletedAt: Date,
         isCompleted: Bool = false,
         completionDate: Date? = nil) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.isAllDay = isAllDay
        self.priority = priority
        self.calendarIdentifier = calendarIdentifier
        self.location = location
        self.deletedAt = deletedAt
        self.isCompleted = isCompleted
        self.completionDate = completionDate
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        notes = try values.decodeIfPresent(String.self, forKey: .notes)
        dueDate = try values.decodeIfPresent(Date.self, forKey: .dueDate)
        isAllDay = try values.decode(Bool.self, forKey: .isAllDay)
        priority = try values.decode(Int.self, forKey: .priority)
        calendarIdentifier = try values.decodeIfPresent(String.self, forKey: .calendarIdentifier)
        location = try values.decodeIfPresent(DeletedLocation.self, forKey: .location)
        deletedAt = try values.decode(Date.self, forKey: .deletedAt)
        isCompleted = try values.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        completionDate = try values.decodeIfPresent(Date.self, forKey: .completionDate)
    }
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
    /// All completed reminders, newest completion first (tab shows top 5).
    @Published private(set) var completedReminders: [EKReminder] = []
    @Published private(set) var allReminders: [EKReminder] = []   // search corpus
    /// Shadow copies of reminders deleted through remr, newest first.
    /// EventKit has no trash — `store.remove` is permanent — so remr snapshots
    /// deletions here to power the "Recently Deleted" tab.
    @Published private(set) var recentlyDeleted: [DeletedReminder] = []
    /// Time of the most recent completed EventKit refresh.
    @Published private(set) var lastSyncDate: Date?
    /// Incomplete reminders due before today / within today (menu bar badge).
    @Published private(set) var overdueCount = 0
    @Published private(set) var dueTodayCount = 0


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
        // EventKit's date-range predicates misfile all-day reminders, so the
        // chronological sections are bucketed in Swift from `allReminders`
        // (ReminderSection in ReminderSections.swift), never from predicates.
        let completedPred = store.predicateForCompletedReminders(withCompletionDateStarting: nil, ending: nil, calendars: nil)
        let allPred = store.predicateForReminders(in: nil)

        fetchGeneration += 1
        let gen = fetchGeneration
        Task { [weak self] in
            guard let self else { return }
            let completedResult = await self.fetchReminders(completedPred)
            guard gen == self.fetchGeneration else { return }
            if let completedResult {
                self.completedReminders = completedResult.sorted { ($0.completionDate ?? .distantPast) > ($1.completionDate ?? .distantPast) }
            }

            let allResult = await self.fetchReminders(allPred)
            guard gen == self.fetchGeneration else { return }
            if let allResult {
                self.allReminders = allResult.sorted { lhs, rhs in
                    if Self.dueAscending(lhs, rhs, Calendar.current) { return true }
                    if Self.dueAscending(rhs, lhs, Calendar.current) { return false }
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
            }
            let calendar = Calendar.current
            let startOfToday = calendar.startOfDay(for: Date())
            let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
            self.overdueCount = self.allReminders.filter { reminder in
                reminder.dueDateComponents
                    .flatMap { calendar.date(from: $0) }
                    .map { $0 < startOfToday } ?? false
            }.count
            self.dueTodayCount = self.allReminders.filter { reminder in
                reminder.dueDateComponents
                    .flatMap { calendar.date(from: $0) }
                    .map { $0 >= startOfToday && $0 < startOfTomorrow } ?? false
            }.count
            self.lastSyncDate = Date()
        }
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

    static func dateComponents(for date: Date?,
                               hasTime: Bool,
                               calendar: Calendar = .current) -> DateComponents? {
        guard let date else { return nil }
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        if hasTime {
            let time = calendar.dateComponents([.hour, .minute, .second], from: date)
            components.hour = time.hour
            components.minute = time.minute
            components.second = time.second
        }
        return components
    }

    func reminder(withIdentifier identifier: String) -> EKReminder? {
        store.calendarItem(withIdentifier: identifier) as? EKReminder
    }

    // MARK: - Mutations

    func deleteReminder(_ reminder: EKReminder) async throws -> DeletedReminder? {
        // EventKit fields must be read while the item still exists.
        let snapshot = snapshotForDeletion(reminder)
        try store.remove(reminder, commit: true)
        if let snapshot {
            recentlyDeleted.insert(snapshot, at: 0)
            persistDeleted()
        }
        refresh()
        return snapshot
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
            deletedAt: Date(),
            isCompleted: reminder.isCompleted,
            completionDate: reminder.completionDate
        )
    }

    /// Re-create a deleted reminder from its snapshot. The snapshot is kept
    /// until both creation and completion-state restoration have succeeded.
    func restore(_ deleted: DeletedReminder) async throws {
        let draft = ReminderDraft.fromDeleted(deleted)
        let recreated = try await create(from: draft)
        recreated.isCompleted = deleted.isCompleted
        recreated.completionDate = deleted.isCompleted ? deleted.completionDate : nil
        try store.save(recreated, commit: true)
        refresh()
        recentlyDeleted.removeAll { $0.id == deleted.id }
        persistDeleted()
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

    func toggleCompletion(_ reminder: EKReminder) async throws -> (wasCompleted: Bool, isCompleted: Bool) {
        guard let latest = self.reminder(withIdentifier: reminder.calendarItemIdentifier) else {
            throw ReminderStoreError.reminderNotFound
        }
        let wasCompleted = latest.isCompleted
        let originalCompletionDate = latest.completionDate
        latest.isCompleted.toggle()
        if !latest.isCompleted {
            latest.completionDate = nil
        }
        do {
            try store.save(latest, commit: true)
            refresh()
            return (wasCompleted: wasCompleted, isCompleted: latest.isCompleted)
        } catch {
            latest.isCompleted = wasCompleted
            latest.completionDate = originalCompletionDate
            throw error
        }
    }
    @MainActor
    func setOngoing(_ reminder: EKReminder, enabled: Bool) async {
        let isOngoing = NaturalLanguageParser.isOngoing(title: reminder.title, notes: reminder.notes)
        guard isOngoing != enabled else { return }

        let originalTitle = reminder.title
        let originalNotes = reminder.notes

        if enabled {
            let tagLine = "#\(NaturalLanguageParser.ongoingTag)"
            reminder.notes = [reminder.notes ?? "", tagLine]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        } else {
            let cleanedTitle = NaturalLanguageParser.removingTag(
                NaturalLanguageParser.ongoingTag,
                from: reminder.title ?? ""
            )
            guard !cleanedTitle.isEmpty else { return }
            reminder.title = cleanedTitle

            let cleanedNotes = NaturalLanguageParser.removingTag(
                NaturalLanguageParser.ongoingTag,
                from: reminder.notes ?? ""
            )
            reminder.notes = cleanedNotes.isEmpty ? nil : cleanedNotes
        }

        do {
            try store.save(reminder, commit: true)
            refresh()
        } catch {
            reminder.title = originalTitle
            reminder.notes = originalNotes
            NSLog("remr: failed to save ongoing toggle: \(error)")
        }
    }


    @discardableResult
    func create(from draft: ReminderDraft) async throws -> EKReminder {
        let calendar = draft.calendarIdentifier.flatMap { store.calendar(withIdentifier: $0) }
        let location: EKStructuredLocation?
        switch draft.location {
        case .none:
            location = nil
        case .unresolved(let phrase):
            throw ReminderStoreError.unresolvedLocation(phrase)
        case .resolved(let deletedLocation):
            location = Self.structuredLocation(from: deletedLocation)
        }
        return try await create(title: draft.title,
                                calendar: calendar,
                                dueDate: Self.dateComponents(for: draft.dueDate, hasTime: draft.hasTime),
                                priority: draft.priority,
                                location: location,
                                notes: draft.persistedNotes)
    }

    func update(_ reminder: EKReminder, from draft: ReminderDraft) async throws {
        guard let latest = self.reminder(withIdentifier: reminder.calendarItemIdentifier) else {
            throw ReminderStoreError.reminderNotFound
        }

        let replacementLocation: EKStructuredLocation?
        switch draft.location {
        case .none:
            replacementLocation = nil
        case .unresolved(let phrase):
            throw ReminderStoreError.unresolvedLocation(phrase)
        case .resolved(let deletedLocation):
            replacementLocation = Self.structuredLocation(from: deletedLocation)
        }

        let calendar = draft.calendarIdentifier.flatMap { store.calendar(withIdentifier: $0) }
            ?? latest.calendar
            ?? store.defaultCalendarForNewReminders()
            ?? reminderCalendars().first
        guard let calendar else { throw ReminderStoreError.noCalendar }

        let originalTitle = latest.title
        let originalNotes = latest.notes
        let originalDueDate = latest.dueDateComponents
        let originalPriority = latest.priority
        let originalCalendar = latest.calendar
        let originalLocationAlarms = (latest.alarms ?? []).filter { $0.structuredLocation != nil }

        latest.calendar = calendar
        latest.title = draft.title
        latest.notes = draft.persistedNotes
        latest.dueDateComponents = Self.dateComponents(for: draft.dueDate, hasTime: draft.hasTime)
        latest.priority = draft.priority
        for alarm in originalLocationAlarms {
            latest.removeAlarm(alarm)
        }
        if let replacementLocation {
            let alarm = EKAlarm(relativeOffset: 0)
            alarm.structuredLocation = replacementLocation
            alarm.proximity = .enter
            latest.addAlarm(alarm)
        }

        do {
            try store.save(latest, commit: true)
            refresh()
        } catch {
            latest.title = originalTitle
            latest.notes = originalNotes
            latest.dueDateComponents = originalDueDate
            latest.priority = originalPriority
            latest.calendar = originalCalendar
            for alarm in (latest.alarms ?? []).filter({ $0.structuredLocation != nil }) {
                latest.removeAlarm(alarm)
            }
            for alarm in originalLocationAlarms {
                latest.addAlarm(alarm)
            }
            throw error
        }
    }

    func snooze(_ reminder: EKReminder, until date: Date?, hasTime: Bool) async throws {
        guard let latest = self.reminder(withIdentifier: reminder.calendarItemIdentifier) else {
            throw ReminderStoreError.reminderNotFound
        }
        let originalDueDate = latest.dueDateComponents
        latest.dueDateComponents = Self.dateComponents(for: date, hasTime: hasTime)
        do {
            try store.save(latest, commit: true)
            refresh()
        } catch {
            latest.dueDateComponents = originalDueDate
            throw error
        }
    }

    /// Move a reminder to a new day, preserving its time-of-day (timed) or
    /// all-day status. Completed reminders are left untouched by callers.
    func reschedule(_ reminder: EKReminder, to targetDay: Date) async throws {
        guard let latest = self.reminder(withIdentifier: reminder.calendarItemIdentifier) else {
            throw ReminderStoreError.reminderNotFound
        }
        let originalDueDate = latest.dueDateComponents
        latest.dueDateComponents = CalendarGridMath.rescheduleComponents(due: originalDueDate,
                                                                         to: targetDay,
                                                                         calendar: .current)
        do {
            try store.save(latest, commit: true)
            refresh()
        } catch {
            latest.dueDateComponents = originalDueDate
            throw error
        }
    }
    /// Create an incomplete copy with the same fields, tags, location, due
    /// date, priority, and list as the source reminder.
    @discardableResult
    func duplicate(_ reminder: EKReminder) async throws -> EKReminder {
        guard let latest = self.reminder(withIdentifier: reminder.calendarItemIdentifier) else {
            throw ReminderStoreError.reminderNotFound
        }
        var draft = ReminderDraft.fromReminder(latest)
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.title = title.isEmpty ? "Reminder copy" : "Copy of \(title)"
        return try await create(from: draft)
    }

    /// Move a reminder to a selected list, or to EventKit's default list when
    /// the identifier is nil.
    func moveToList(_ reminder: EKReminder, calendarIdentifier: String?) async throws {
        guard let latest = self.reminder(withIdentifier: reminder.calendarItemIdentifier) else {
            throw ReminderStoreError.reminderNotFound
        }
        let calendar = calendarIdentifier.flatMap { store.calendar(withIdentifier: $0) }
            ?? store.defaultCalendarForNewReminders()
            ?? reminderCalendars().first
        guard let calendar else { throw ReminderStoreError.noCalendar }

        let original = latest.calendar
        latest.calendar = calendar
        do {
            try store.save(latest, commit: true)
            refresh()
        } catch {
            latest.calendar = original
            throw error
        }
    }


    private static func structuredLocation(from location: DeletedLocation) -> EKStructuredLocation {
        let structured = EKStructuredLocation()
        structured.title = location.title
        structured.geoLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
        structured.radius = location.radius
        return structured
    }

    @discardableResult
    private func create(title: String,
                        calendar: EKCalendar?,
                        dueDate: DateComponents?,
                        priority: Int,
                        location: EKStructuredLocation?,
                        notes: String? = nil) async throws -> EKReminder {
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

    func allTags() -> [String] {
        let tags = (allReminders + completedReminders).flatMap { reminder in
            NaturalLanguageParser.extractTags(from: [reminder.title ?? "", reminder.notes ?? ""].joined(separator: " "))
        }
        return Array(Set(tags.map { $0.lowercased() })).sorted()
    }
    /// Rename a tag in every reminder managed by remr, preserving all other
    /// EventKit fields and rolling back already-saved items if a later save
    /// fails.
    func renameTag(_ tag: String, to replacement: String) throws {
        let old = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let new = replacement.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !old.isEmpty, !new.isEmpty, !new.contains(where: { $0.isWhitespace }), old != new else { return }

        let changes = managedReminders.compactMap { reminder -> (reminder: EKReminder, title: String, notes: String?)? in
            guard let latest = self.reminder(withIdentifier: reminder.calendarItemIdentifier) else { return nil }
            let title = NaturalLanguageParser.replacingTag(old, with: new, in: latest.title ?? "")
            let notesText = NaturalLanguageParser.replacingTag(old, with: new, in: latest.notes ?? "")
            let notes = notesText.isEmpty ? nil : notesText
            guard title != latest.title || notes != latest.notes else { return nil }
            return (latest, title, notes)
        }
        try saveTagChanges(changes)
    }

    /// Remove a tag from every reminder. A title-only tag is rejected rather
    /// than turning a valid reminder into an empty EventKit title.
    func removeTag(_ tag: String) throws {
        let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return }

        let changes = managedReminders.compactMap { reminder -> (reminder: EKReminder, title: String, notes: String?)? in
            guard let latest = self.reminder(withIdentifier: reminder.calendarItemIdentifier) else { return nil }
            let title = NaturalLanguageParser.removingTag(normalized, from: latest.title ?? "")
            let notesText = NaturalLanguageParser.removingTag(normalized, from: latest.notes ?? "")
            let notes = notesText.isEmpty ? nil : notesText
            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (latest, "", notes)
            }
            guard title != latest.title || notes != latest.notes else { return nil }
            return (latest, title, notes)
        }
        if changes.contains(where: { $0.title.isEmpty }) {
            throw ReminderStoreError.tagRemovalWouldEmptyTitle(normalized)
        }
        try saveTagChanges(changes)
    }

    /// All current and completed EventKit reminders, deduplicated by ID.
    private var managedReminders: [EKReminder] {
        var seen = Set<String>()
        return (allReminders + completedReminders).filter { seen.insert($0.calendarItemIdentifier).inserted }
    }

    private func saveTagChanges(_ changes: [(reminder: EKReminder, title: String, notes: String?)]) throws {
        guard !changes.isEmpty else { return }
        var originals: [(reminder: EKReminder, title: String?, notes: String?)] = []
        do {
            for change in changes {
                originals.append((change.reminder, change.reminder.title, change.reminder.notes))
                change.reminder.title = change.title
                change.reminder.notes = change.notes
                try store.save(change.reminder, commit: true)
            }
        } catch {
            for original in originals {
                original.reminder.title = original.title
                original.reminder.notes = original.notes
                try? store.save(original.reminder, commit: true)
            }
            throw error
        }
        refresh()
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
