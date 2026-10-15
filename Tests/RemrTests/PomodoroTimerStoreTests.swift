import AppKit
import Combine
import Foundation
import SwiftUI
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

    func testMenuBarCountdownPublishesOnlyEveryTenSeconds() throws {
        let timer = PomodoroTimerStore(defaults: makeDefaults())
        var titles: [String?] = []
        let subscription = timer.$menuBarTitle.sink { titles.append($0) }
        defer { subscription.cancel() }

        timer.start()
        let start = try XCTUnwrap(timer.endDate).addingTimeInterval(-25 * 60)
        XCTAssertEqual(timer.menuBarTitle, "25:00")

        for second in 1...9 {
            timer.tick(at: start.addingTimeInterval(Double(second)))
        }
        XCTAssertEqual(timer.formattedRemaining, "24:51")
        XCTAssertEqual(titles, [nil, "25:00"])

        timer.tick(at: start.addingTimeInterval(10))
        XCTAssertEqual(titles, [nil, "25:00", "24:50"])
        timer.tick(at: start.addingTimeInterval(19))
        XCTAssertEqual(titles, [nil, "25:00", "24:50"])
        timer.tick(at: start.addingTimeInterval(20))
        XCTAssertEqual(titles, [nil, "25:00", "24:50", "24:40"])
    }

    func testPauseResetAndSkipClearMenuBarCountdownImmediately() {
        let timer = PomodoroTimerStore(defaults: makeDefaults())
        XCTAssertNil(timer.menuBarTitle)
        timer.start()
        XCTAssertEqual(timer.menuBarTitle, "25:00")
        timer.pause()
        XCTAssertNil(timer.menuBarTitle)
        timer.start()
        XCTAssertNotNil(timer.menuBarTitle)
        timer.reset()
        XCTAssertNil(timer.menuBarTitle)
        timer.start()
        timer.skip()
        XCTAssertNil(timer.menuBarTitle)
        timer.start()
        XCTAssertEqual(timer.menuBarTitle, "05:00")
    }

    func testCompletionClearsMenuBarCountdownAndCountsSessionOnce() throws {
        let timer = PomodoroTimerStore(defaults: makeDefaults())
        timer.start()
        let end = try XCTUnwrap(timer.endDate)
        timer.tick(at: end)

        XCTAssertNil(timer.menuBarTitle)
        XCTAssertFalse(timer.isRunning)
        XCTAssertEqual(timer.remaining, 0)
        XCTAssertEqual(timer.completedFocusSessions, 1)
        XCTAssertEqual(timer.completion?.completedAt, end)
        timer.tick(at: end.addingTimeInterval(10))
        XCTAssertEqual(timer.completedFocusSessions, 1)
    }

    func testRestoredRunningTimerHasMenuBarCountdown() {
        let defaults = makeDefaults()
        let timer = PomodoroTimerStore(defaults: defaults)
        timer.startNextPhase()

        let restored = PomodoroTimerStore(defaults: defaults)
        XCTAssertEqual(restored.phase, .shortBreak)
        XCTAssertEqual(restored.menuBarTitle, "05:00")
        restored.pause()
        timer.pause()
    }

    func testIdleTicksDoNotPublishClockChanges() {
        let timer = PomodoroTimerStore(defaults: makeDefaults())
        var changes = 0
        let subscription = timer.objectWillChange.sink { changes += 1 }
        defer { subscription.cancel() }
        timer.tick(at: Date().addingTimeInterval(10))
        XCTAssertEqual(changes, 0)
    }

    func testTimerPanelFitsAtItsNaturalHeight() {
        _ = NSApplication.shared
        let timer = PomodoroTimerStore(defaults: makeDefaults())
        let hosting = NSHostingView(rootView: PomodoroTimerView(timer: timer).frame(width: 400))
        hosting.layoutSubtreeIfNeeded()

        XCTAssertEqual(hosting.fittingSize.width, 400)
        XCTAssertLessThanOrEqual(hosting.fittingSize.height, 200)
        XCTAssertGreaterThan(hosting.fittingSize.height, 150)
    }

    func testTimerSectionIsRemovedAfterRepeatedClosing() {
        _ = NSApplication.shared
        let timer = PomodoroTimerStore(defaults: makeDefaults())
        let hosting = NSHostingView(rootView:
            PomodoroPanelSection(isPresented: false, timer: timer).frame(width: 400))
        for _ in 0..<5 {
            hosting.rootView = PomodoroPanelSection(isPresented: true, timer: timer).frame(width: 400)
            hosting.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(hosting.fittingSize.height, 150)

            hosting.rootView = PomodoroPanelSection(isPresented: false, timer: timer).frame(width: 400)
            hosting.layoutSubtreeIfNeeded()
            XCTAssertEqual(hosting.fittingSize.height, 0)
        }
    }

    func testTimerSectionFitsInsideTheExistingWindow() {
        _ = NSApplication.shared
        let timer = PomodoroTimerStore(defaults: makeDefaults())
        func content(presented: Bool) -> some View {
            VStack(spacing: 0) {
                Color.clear.frame(height: presented ? 397 : 580)
                Text("Updated just now")
                    .font(.system(size: 10))
                    .frame(height: 20)
                Color.clear.frame(height: MainPopoverLayout.pomodoroHeaderHeight)
                PomodoroPanelSection(isPresented: presented, timer: timer)
            }
            .frame(width: 400)
        }
        let hosting = NSHostingView(rootView: content(presented: false))
        hosting.layoutSubtreeIfNeeded()
        let closedSize = hosting.fittingSize
        hosting.rootView = content(presented: true)
        hosting.layoutSubtreeIfNeeded()

        XCTAssertEqual(closedSize, NSSize(width: 400, height: MainPopoverLayout.height(pomodoroEnabled: true)))
        XCTAssertEqual(hosting.fittingSize, closedSize)
    }
}
