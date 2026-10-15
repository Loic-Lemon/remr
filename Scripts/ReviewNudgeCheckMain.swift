import Foundation

/// Standalone because Command Line Tools does not include XCTest.framework.
@main
struct ReviewNudgeChecks {
    @MainActor
    static func main() {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            checks += 1
            print("PASS: \(message)")
        }
        let start = Date(timeIntervalSince1970: 1_000_000)
        var schedule = ReviewNudgeSchedule()
        check(!schedule.isDue(at: start), "An unscheduled check-in does not fire")
        schedule.schedule(after: start, minimumMinutes: 90, maximumMinutes: 180, sample: 0)
        check(schedule.nextDueAt == start.addingTimeInterval(5_400), "Earliest nudge is 90 minutes away")
        check(!schedule.isDue(at: start.addingTimeInterval(5_399)), "A nudge never fires before its deadline")
        check(schedule.isDue(at: start.addingTimeInterval(5_400)), "A nudge becomes due at its chosen deadline")
        schedule.schedule(after: start, minimumMinutes: 90, maximumMinutes: 180, sample: 1)
        check(schedule.nextDueAt == start.addingTimeInterval(10_800), "Latest sampled delay is three hours")
        schedule.schedule(after: start, minimumMinutes: 90, maximumMinutes: 180, sample: 0.5)
        check(schedule.nextDueAt == start.addingTimeInterval(8_100), "The midpoint sample produces 2 hours 15 minutes")
        let deadline = schedule.nextDueAt
        for offset in stride(from: 0, through: 9_000, by: 30) {
            _ = schedule.isDue(at: start.addingTimeInterval(Double(offset)))
        }
        check(schedule.nextDueAt == deadline, "Polling does not re-roll the random deadline")
        check(ReviewNudgeSchedule(nextDueAt: deadline).nextDueAt == deadline,
              "Restoring a persisted deadline preserves it")
        schedule.schedule(after: start.addingTimeInterval(3_600), minimumMinutes: 90,
                          maximumMinutes: 180, sample: 0)
        check(schedule.nextDueAt == start.addingTimeInterval(9_000), "A review restarts the full minimum interval")
        schedule.clear()
        check(!schedule.isDue(at: .distantFuture), "Disabling clears the pending check-in")
        let samples = (0...1_000).map {
            ReviewNudgeTiming.delay(minimumMinutes: 90, maximumMinutes: 180, sample: Double($0) / 1_000)
        }
        check(samples.allSatisfy { (5_400...10_800).contains($0) }, "Every sampled delay respects both bounds")

        let suite = "remr.test.review-nudges.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        check(settings.reviewNudgesEnabled && settings.reviewNudgeMinimumMinutes == 90
              && settings.reviewNudgeMaximumMinutes == 180, "Fresh settings enable the requested 90–180 minute range")
        settings.setReviewNudgeMinimumMinutes(210)
        check(settings.reviewNudgeMaximumMinutes == 210, "Raising the minimum keeps the maximum valid")
        settings.setReviewNudgeMaximumMinutes(60)
        check(settings.reviewNudgeMinimumMinutes == 60, "Lowering the maximum keeps the minimum valid")
        settings.setReviewNudgesEnabled(false)
        let reloaded = SettingsStore(defaults: defaults)
        check(!reloaded.reviewNudgesEnabled && reloaded.reviewNudgeMinimumMinutes == 60
              && reloaded.reviewNudgeMaximumMinutes == 60, "Enabled state and interval bounds survive a restart")
        check(ReviewNudgeTiming.delay(minimumMinutes: 60, maximumMinutes: 60, sample: 0.9) == 3_600,
              "Equal bounds support a fixed interval")
        settings.setReviewNudgeMinimumMinutes(.nan)
        check(settings.reviewNudgeMinimumMinutes == 90, "Non-finite settings fall back to a valid interval")
        check(ReviewNudgeTiming.label(minutes: 90) == "1 hr 30 min", "Settings show readable interval labels")
        print("\(checks) review-nudge checks passed")
    }
}
