import Foundation

/// A new uniformly random delay is chosen for each check-in, never on a tick.
enum ReviewNudgeTiming {
    static let defaultMinimumMinutes: Double = 90
    static let defaultMaximumMinutes: Double = 180
    static let allowedMinutes: ClosedRange<Double> = 30...360

    static func clampedMinutes(_ value: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, allowedMinutes.lowerBound), allowedMinutes.upperBound)
    }

    static func delay(minimumMinutes: Double, maximumMinutes: Double, sample: Double) -> TimeInterval {
        let lower = clampedMinutes(minimumMinutes, fallback: defaultMinimumMinutes)
        let upper = max(lower, clampedMinutes(maximumMinutes, fallback: defaultMaximumMinutes))
        let fraction = sample.isFinite ? min(max(sample, 0), 1) : 0.5
        return (lower + (upper - lower) * fraction) * 60
    }

    static func label(minutes: Double) -> String {
        let value = Int(minutes)
        let hours = value / 60, remainder = value % 60
        if hours == 0 { return "\(remainder) min" }
        return remainder == 0 ? "\(hours) hr" : "\(hours) hr \(remainder) min"
    }
}

struct ReviewNudgeSchedule {
    private(set) var nextDueAt: Date?

    init(nextDueAt: Date? = nil) { self.nextDueAt = nextDueAt }

    mutating func schedule(after date: Date, minimumMinutes: Double,
                           maximumMinutes: Double, sample: Double) {
        nextDueAt = date.addingTimeInterval(ReviewNudgeTiming.delay(
            minimumMinutes: minimumMinutes, maximumMinutes: maximumMinutes, sample: sample))
    }

    mutating func clear() { nextDueAt = nil }

    func isDue(at date: Date) -> Bool {
        nextDueAt.map { date >= $0 } ?? false
    }
}
