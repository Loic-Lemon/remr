import AppKit
import EventKit
import Foundation
@testable import remr

@main
struct DemoCheckMain {
    @MainActor
    static func main() async throws {
        precondition(DemoEnvironment.isEnabled, "Run this harness with --demo")
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
            print("PASS: \(message)")
        }
        let deletedURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("remr/deleted.json")
        let deletedBefore = try? Data(contentsOf: deletedURL)
        let personalPreferences = (UserDefaults.standard.persistentDomain(forName: "com.local.remr") ?? [:]) as NSDictionary
        let store = ReminderStore()
        store.start()
        await store.requestAccess()
        check(store.accessState == .authorized, "Demo starts without a permission request")
        check(store.allReminders.count == 8 && store.completedReminders.count == 1, "Fictional seed data is loaded")
        check(Set(store.allReminders.map(\.calendarItemIdentifier)).count == 8, "Unsaved reminders have unique selectable IDs")
        check(store.reminderCalendars().map(\.title) == ["Work", "Personal", "Errands"], "Only fictional lists are exposed")
        check(store.recentlyDeleted.isEmpty, "Personal deleted reminders are not loaded")
        check(SettingsStore.shared.notchPopover && !SettingsStore.shared.reviewNudgesEnabled && !SettingsStore.shared.ollamaEnabled,
              "Demo settings use the notch without automatic nudges or local models")
        let parsed = NaturalLanguageParser.parse("Send proposal tomorrow at 10am @work", listNames: store.reminderCalendars().map(\.title))
        let work = store.resolveList(token: "work").calendar!
        let created = try await store.create(from: ReminderDraft.fromParsed(parsed, notes: "", calendar: work))
        check(created.title == "Send proposal" && created.calendar == work && created.dueDateComponents?.hour == 10,
              "Scripted natural-language capture works")
        check(store.reminder(withIdentifier: created.calendarItemIdentifier) === created, "Created reminder is available for selection")
        let target = Calendar.current.date(byAdding: .day, value: 2, to: Date())!
        try await store.reschedule(created, to: target)
        check(created.dueDateComponents?.day == Calendar.current.component(.day, from: target)
              && created.dueDateComponents?.hour == 10, "Calendar rescheduling preserves the time")
        _ = try await store.toggleCompletion(created)
        check(created.isCompleted && store.completedReminders.contains(created), "Completion updates the UI corpus")
        _ = try await store.toggleCompletion(created)
        var draft = ReminderDraft.fromReminder(created)
        draft.title = "Send revised proposal"
        draft.tags = ["demo"]
        try await store.update(created, from: draft)
        try store.renameTag("demo", to: "planning")
        check(created.title == draft.title && store.allTags().contains("planning"), "Editing and tag mutations remain in memory")
        try await store.moveToList(created, calendarIdentifier: store.reminderCalendars()[1].calendarIdentifier)
        check(created.calendar.title == "Personal", "Moving between fictional lists works")
        try await store.snooze(created, until: nil, hasTime: false)
        check(created.dueDateComponents == nil, "Snoozing can clear the due date")
        let copy = try await store.duplicate(created)
        check(copy.calendarItemIdentifier != created.calendarItemIdentifier, "Duplication gets a new identity")
        let deleted = try await store.deleteReminder(created)!
        check(store.reminder(withIdentifier: created.calendarItemIdentifier) == nil && store.recentlyDeleted.count == 1,
              "Deletion updates only the demo store")
        try await store.restore(deleted)
        check(store.recentlyDeleted.isEmpty, "Deleted demo reminders can be restored")
        let fresh = ReminderStore()
        fresh.start()
        check(fresh.allReminders.count == 8 && !fresh.allReminders.contains { $0.title == draft.title }, "A fresh store resets the take")
        check((try? Data(contentsOf: deletedURL)) == deletedBefore, "Personal deleted-reminder file is unchanged")
        check((UserDefaults.standard.persistentDomain(forName: "com.local.remr") ?? [:]) as NSDictionary == personalPreferences, "Personal preferences are unchanged")
        print("Demo checks passed (\(checks)).")
    }
}
