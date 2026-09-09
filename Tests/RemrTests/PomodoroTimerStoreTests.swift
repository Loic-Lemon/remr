import Foundation
import XCTest
@testable import remr

@MainActor
final class PomodoroTimerStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "remr.test.pomodoro.\(UUID().uuidString)")!
    }

    func testDefaultsUseClassicDurations() {
        let timer = PomodoroTimerStore(defaults: makeDefaults())

        XCTAssertEqual(timer.phase, .focus)
        XCTAssertEqual(timer.focusMinutes, 25)
        XCTAssertEqual(timer.shortBreakMinutes, 5)
        XCTAssertFalse(timer.isRunning)
        XCTAssertEqual(timer.remaining, 25 * 60, accuracy: 0.1)
    }

    func testDurationsPersistAndResetCurrentPhase() {
        let defaults = makeDefaults()
        let timer = PomodoroTimerStore(defaults: defaults)

        timer.setDuration(40, for: .focus)
        timer.start()
        timer.pause()

        let reloaded = PomodoroTimerStore(defaults: defaults)
        XCTAssertEqual(reloaded.focusMinutes, 40)
        XCTAssertFalse(reloaded.isRunning)
        XCTAssertGreaterThan(reloaded.remaining, 0)
        XCTAssertLessThanOrEqual(reloaded.remaining, 40 * 60)
    }

    func testStartNextPhaseAdvancesAndRuns() {
        let timer = PomodoroTimerStore(defaults: makeDefaults())

        timer.startNextPhase()

        XCTAssertEqual(timer.phase, .shortBreak)
        XCTAssertTrue(timer.isRunning)
        timer.pause()
    }
}
