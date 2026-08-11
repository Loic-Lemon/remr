import EventKit
import XCTest
@testable import remr

final class ReminderDraftTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ year: Int = 2026, _ month: Int = 8, _ day: Int = 11,
                      _ hour: Int? = nil, _ minute: Int? = nil) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    func testPersistedNotesNormalizesTagsAndKeepsNotesBody() {
        let draft = ReminderDraft(
            title: "Buy milk",
            notes: "Remember oat milk",
            tags: ["#Groceries", "groceries", " Errands ", "#errands"]
        )

        XCTAssertEqual(draft.persistedNotes, "Remember oat milk\n#Groceries #Errands")
    }

    func testPersistedNotesEmptyTagsAndEmptyNotes() {
        XCTAssertNil(ReminderDraft(title: "A reminder").persistedNotes)
        XCTAssertEqual(ReminderDraft(title: "A reminder", notes: "Details").persistedNotes, "Details")
        XCTAssertEqual(ReminderDraft(title: "A reminder", notes: " ", tags: ["tag"]).persistedNotes, "#tag")
    }

    func testPersistedNotesReplacesExistingCanonicalTrailingTagLine() {
        let draft = ReminderDraft(
            title: "A reminder",
            notes: "Details\n#old #second",
            tags: ["new"]
        )

        XCTAssertEqual(draft.persistedNotes, "Details\n#new")
    }

    func testPersistedNotesPreservesNoncanonicalNotes() {
        let notes = "Details\n#tag, is important"
        let draft = ReminderDraft(title: "A reminder", notes: notes, tags: ["new"])

        XCTAssertEqual(draft.persistedNotes, notes + "\n#new")
    }

    func testPersistedNotesPreservesPunctuationBearingLegacyTagLine() {
        let draft = ReminderDraft(title: "A reminder", notes: "#old,", tags: ["new"])

        XCTAssertEqual(draft.persistedNotes, "#old,\n#new")
    }

    func testFromParsedMapsParserFieldsAndUnresolvedLocation() {
        let now = date(hour: 10)
        let parsed = NaturalLanguageParser.parse(
            "buy milk tomorrow at 5pm @Home #Groceries",
            now: now,
            calendar: calendar,
            listNames: ["Home"]
        )
        let list = EKCalendar(for: .reminder, eventStore: EKEventStore())
        list.title = "Home"
        let draft = ReminderDraft.fromParsed(parsed, notes: "Details", calendar: list)

        XCTAssertEqual(draft.rawInput, parsed.original)
        XCTAssertEqual(draft.title, parsed.title)
        XCTAssertEqual(draft.notes, "Details")
        XCTAssertEqual(draft.dueDate, parsed.dueDate)
        XCTAssertEqual(draft.hasTime, parsed.hasTime)
        XCTAssertEqual(draft.priority, parsed.priority)
        XCTAssertEqual(draft.calendarIdentifier, list.calendarIdentifier)
        XCTAssertEqual(draft.calendarTitle, "Home")
        XCTAssertEqual(draft.tags, ["Groceries"])
        XCTAssertEqual(draft.diagnostics, parsed.diagnostics)
        XCTAssertEqual(draft.location, .none)
    }

    func testFromParsedMapsLocationAsUnresolved() {
        let parsed = NaturalLanguageParser.parse("buy milk at the office", now: date(hour: 10), calendar: calendar)
        let draft = ReminderDraft.fromParsed(parsed, notes: "", calendar: nil)

        XCTAssertEqual(draft.location, .unresolved("the office"))
    }

    func testFromReminderRemovesTitleTagsAndCanonicalNotesLine() {
        let reminder = EKReminder(eventStore: EKEventStore())
        reminder.title = "Buy #Groceries milk"
        reminder.notes = "Remember oat milk\n#groceries #Errands"
        reminder.dueDateComponents = calendar.dateComponents([.year, .month, .day], from: date())
        reminder.priority = 5

        let draft = ReminderDraft.fromReminder(reminder)

        XCTAssertEqual(draft.title, "Buy milk")
        XCTAssertEqual(draft.notes, "Remember oat milk")
        XCTAssertEqual(draft.tags, ["Groceries", "Errands"])
        XCTAssertEqual(draft.dueDate, date())
        XCTAssertFalse(draft.hasTime)
        XCTAssertEqual(draft.priority, 5)
        XCTAssertEqual(draft.location, .none)
        XCTAssertTrue(draft.diagnostics.isEmpty)
    }

    func testFromReminderMapsTimedDateAndStructuredLocation() {
        let reminder = EKReminder(eventStore: EKEventStore())
        reminder.title = "Visit office"
        reminder.dueDateComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute],
                                                              from: date(2026, 8, 12, 14, 30))
        let structured = EKStructuredLocation()
        structured.title = "Office"
        structured.geoLocation = CLLocation(latitude: 1.25, longitude: -2.5)
        structured.radius = 100
        let alarm = EKAlarm(relativeOffset: 0)
        alarm.structuredLocation = structured
        reminder.addAlarm(alarm)

        let draft = ReminderDraft.fromReminder(reminder)

        XCTAssertEqual(draft.dueDate, date(2026, 8, 12, 14, 30))
        XCTAssertTrue(draft.hasTime)
        XCTAssertEqual(draft.location, .resolved(DeletedLocation(title: "Office", latitude: 1.25, longitude: -2.5, radius: 100)))
    }

    func testFromDeletedMapsFieldsAndUsesStableDeletedID() {
        let id = UUID()
        let deleted = DeletedReminder(
            id: id,
            title: "Buy #Groceries milk",
            notes: "Details\n#groceries",
            dueDate: date(2026, 8, 12, 9),
            isAllDay: false,
            priority: 1,
            calendarIdentifier: "home-id",
            location: DeletedLocation(title: "Home", latitude: 1, longitude: 2, radius: 100),
            deletedAt: date()
        )
        let draft = ReminderDraft.fromDeleted(deleted)

        XCTAssertEqual(draft.id, id)
        XCTAssertEqual(draft.title, "Buy milk")
        XCTAssertEqual(draft.notes, "Details")
        XCTAssertEqual(draft.tags, ["Groceries"])
        XCTAssertEqual(draft.dueDate, deleted.dueDate)
        XCTAssertTrue(draft.hasTime)
        XCTAssertEqual(draft.priority, 1)
        XCTAssertEqual(draft.calendarIdentifier, "home-id")
        XCTAssertEqual(draft.location, .resolved(deleted.location!))
        XCTAssertTrue(draft.diagnostics.isEmpty)
    }
}
