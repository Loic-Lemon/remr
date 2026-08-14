import XCTest
@testable import remr

final class SnoozeSurfaceTests: XCTestCase {
    func testFixedChoiceContractUsesSpecifiedOrderAndLabels() {
        var emitted: [SnoozeChoice] = []
        let menu = SnoozeMenu(
            onChoice: { emitted.append($0) },
            onCustom: {},
            onClear: {}
        )

        let orderedChoices: [(label: String, choice: SnoozeChoice)] = [
            ("1 hour", .oneHour),
            ("Later today", .laterToday),
            ("Tomorrow morning", .tomorrowMorning),
            ("Tomorrow evening", .tomorrowEvening),
            ("Next Monday", .nextMonday),
            ("This weekend", .thisWeekend)
        ]

        orderedChoices.forEach { menu.onChoice($0.choice) }

        XCTAssertEqual(
            orderedChoices.map(\.label),
            ["1 hour", "Later today", "Tomorrow morning", "Tomorrow evening", "Next Monday", "This weekend"]
        )
        XCTAssertEqual(emitted, orderedChoices.map(\.choice))
    }

    func testCustomActionEmitsThroughOnCustom() {
        var customActionCount = 0
        let menu = SnoozeMenu(
            onChoice: { _ in },
            onCustom: { customActionCount += 1 },
            onClear: {}
        )

        menu.onCustom()

        XCTAssertEqual(customActionCount, 1)
    }

    func testClearActionEmitsNilDateAndFalseHasTime() {
        var savedDate: Date? = Date(timeIntervalSinceReferenceDate: 123)
        var savedHasTime = true
        let picker = SnoozeDatePickerView(
            initialDate: Date(timeIntervalSinceReferenceDate: 456),
            initialHasTime: true,
            onCancel: {},
            onSave: { date, hasTime in
                savedDate = date
                savedHasTime = hasTime
            }
        )

        picker.onSave(nil, false)

        XCTAssertNil(savedDate)
        XCTAssertFalse(savedHasTime)
    }

    func testDatePickerPreservesTimedAndAllDayValues() {
        let selectedDate = Date(timeIntervalSinceReferenceDate: 789)
        var saves: [(Date?, Bool)] = []
        let picker = SnoozeDatePickerView(
            initialDate: selectedDate,
            initialHasTime: true,
            onCancel: {},
            onSave: { date, hasTime in
                saves.append((date, hasTime))
            }
        )

        picker.onSave(selectedDate, true)
        picker.onSave(selectedDate, false)

        XCTAssertEqual(saves.count, 2)
        XCTAssertEqual(saves[0].0, selectedDate)
        XCTAssertTrue(saves[0].1)
        XCTAssertEqual(saves[1].0, selectedDate)
        XCTAssertFalse(saves[1].1)
    }
}
