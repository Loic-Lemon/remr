import CoreLocation
import EventKit
import XCTest
@testable import remr

/// Pure coverage for the value model used by ReminderEditView. These fixtures
/// never save through EventKit; they only exercise the draft codec and state
/// transitions that the editor passes to ReminderStore.update(_:from:).
final class ReminderEditViewTests: XCTestCase {
    private let calendar: Calendar = Calendar.current

    private func date(_ year: Int = 2026, _ month: Int = 8, _ day: Int,
                      hour: Int? = nil, minute: Int? = nil) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    private func reminder(title: String = "Reminder") -> EKReminder {
        let reminder = EKReminder(eventStore: EKEventStore())
        reminder.title = title
        return reminder
    }

    private func components(of date: Date?) -> DateComponents {
        guard let date else { return DateComponents() }
        return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    func testExistingTitleIsNotReparsedForDatesOrPriority() {
        let reminder = reminder(title: "Review tomorrow high priority")
        let storedDate = date(2026, 8, 14, hour: 16, minute: 20)
        reminder.dueDateComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute], from: storedDate)
        reminder.priority = 9

        let draft = ReminderDraft.fromReminder(reminder)

        XCTAssertEqual(draft.title, "Review tomorrow high priority")
        XCTAssertEqual(components(of: draft.dueDate), components(of: storedDate))
        XCTAssertTrue(draft.hasTime)
        XCTAssertEqual(draft.priority, 9)
        XCTAssertTrue(draft.diagnostics.isEmpty)
    }

    func testTagsRoundTripThroughPersistedNotesAfterOpeningForEdit() {
        let reminder = reminder(title: "Plan #Home visit")
        reminder.notes = "Bring documents\n#home #Errands"

        let opened = ReminderDraft.fromReminder(reminder)

        XCTAssertEqual(opened.title, "Plan visit")
        XCTAssertEqual(opened.notes, "Bring documents")
        XCTAssertEqual(opened.tags, ["Home", "Errands"])
        XCTAssertEqual(opened.persistedNotes, "Bring documents\n#Home #Errands")

        var edited = opened
        edited.tags = ["#Work", "work", " Errands "]
        XCTAssertEqual(edited.persistedNotes, "Bring documents\n#Work #Errands")
    }

    func testAllDayAndTimedDueComponentsMapToDraft() {
        let allDay = reminder(title: "All day")
        let allDayDate = date(2026, 8, 18)
        allDay.dueDateComponents = calendar.dateComponents(
            [.year, .month, .day], from: allDayDate)

        let timed = reminder(title: "Timed")
        let timedDate = date(2026, 8, 18, hour: 9, minute: 45)
        timed.dueDateComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute], from: timedDate)

        let allDayDraft = ReminderDraft.fromReminder(allDay)
        let timedDraft = ReminderDraft.fromReminder(timed)

        XCTAssertEqual(components(of: allDayDraft.dueDate), components(of: allDayDate))
        XCTAssertFalse(allDayDraft.hasTime)
        XCTAssertEqual(components(of: timedDraft.dueDate), components(of: timedDate))
        XCTAssertTrue(timedDraft.hasTime)
    }

    func testClearingDueDateAndLocationIsRepresentableInEditedDraft() {
        let reminder = reminder(title: "Visit office")
        reminder.dueDateComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute], from: date(2026, 8, 20, hour: 10))
        let location = EKStructuredLocation()
        location.title = "Office"
        location.geoLocation = CLLocation(latitude: 1.25, longitude: -2.5)
        location.radius = 100
        let alarm = EKAlarm(relativeOffset: 0)
        alarm.structuredLocation = location
        reminder.addAlarm(alarm)

        let opened = ReminderDraft.fromReminder(reminder)
        XCTAssertNotEqual(opened.location, .none)
        XCTAssertNotNil(opened.dueDate)

        var cleared = opened
        cleared.dueDate = nil
        cleared.hasTime = false
        cleared.location = .none

        XCTAssertNil(cleared.dueDate)
        XCTAssertFalse(cleared.hasTime)
        XCTAssertEqual(cleared.location, .none)
    }

    func testFailedLocationResolutionLeavesOriginalDraftUnchanged() {
        let original = ReminderDraft(
            title: "Visit office",
            notes: "Bring badge",
            dueDate: date(2026, 8, 21, hour: 10),
            hasTime: true,
            priority: 1,
            location: .resolved(DeletedLocation(title: "Office",
                                                 latitude: 1.25,
                                                 longitude: -2.5,
                                                 radius: 100)),
            tags: ["Work"])

        // ReminderEditView prepares a candidate copy before geocoding. A
        // failed lookup must not assign that unresolved candidate back to the
        // editor, so the existing structured location remains intact.
        var candidate = original
        candidate.location = .unresolved("Not a real place")
        let geocodeResult: DeletedLocation? = nil
        if let geocodeResult {
            candidate.location = .resolved(geocodeResult)
        } else {
            candidate = original
        }

        XCTAssertEqual(candidate, original)
        XCTAssertEqual(candidate.location, original.location)
        XCTAssertEqual(candidate.title, "Visit office")
        XCTAssertEqual(candidate.persistedNotes, original.persistedNotes)
    }
}
