import Combine
import Foundation

/// Persisted Pomodoro state. The end date, rather than a decrementing counter,
/// keeps the timer accurate while the popover is closed or the app is inactive.
enum PomodoroPhase: String, CaseIterable, Codable {
    case focus
    case shortBreak

    var title: String {
        self == .focus ? "Focus" : "Short break"
    }

    var next: PomodoroPhase {
        self == .focus ? .shortBreak : .focus
    }
}

struct PomodoroCompletion {
    let phase: PomodoroPhase
    let completedAt: Date
}

@MainActor
final class PomodoroTimerStore: ObservableObject {
    static let shared = PomodoroTimerStore()

    @Published private(set) var phase: PomodoroPhase
    @Published private(set) var isRunning: Bool
    @Published private(set) var endDate: Date?
    @Published private(set) var pausedRemaining: TimeInterval
    @Published private(set) var completedFocusSessions: Int
    @Published private(set) var completion: PomodoroCompletion?
    /// Published clock value keeps SwiftUI's computed remaining time moving.
    @Published private(set) var now = Date()
    @Published private(set) var focusMinutes: Int
    @Published private(set) var shortBreakMinutes: Int

    private let defaults: UserDefaults
    private var ticker: Timer?

    private let phaseKey = "remr.pomodoro.phase"
    private let runningKey = "remr.pomodoro.running"
    private let endDateKey = "remr.pomodoro.endDate"
    private let remainingKey = "remr.pomodoro.remaining"
    private let completedKey = "remr.pomodoro.completed"
    private let focusKey = "remr.pomodoro.focusMinutes"
    private let shortBreakKey = "remr.pomodoro.shortBreakMinutes"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loadedPhase = PomodoroPhase(rawValue: defaults.string(forKey: phaseKey) ?? "") ?? .focus
        let loadedFocus = Self.minutes(defaults.integer(forKey: focusKey), fallback: 25)
        let loadedShortBreak = Self.minutes(defaults.integer(forKey: shortBreakKey), fallback: 5)
        phase = loadedPhase
        focusMinutes = loadedFocus
        shortBreakMinutes = loadedShortBreak
        completedFocusSessions = max(0, defaults.integer(forKey: completedKey))
        let defaultRemaining = loadedPhase == .focus ? loadedFocus : loadedShortBreak
        pausedRemaining = defaults.object(forKey: remainingKey) as? Double
            ?? Double(defaultRemaining * 60)
        isRunning = defaults.bool(forKey: runningKey)
        endDate = defaults.object(forKey: endDateKey).flatMap { value in
            guard let seconds = value as? Double else { return nil }
            return Date(timeIntervalSince1970: seconds)
        }

        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if isRunning { tick() }
    }

    deinit {
        ticker?.invalidate()
    }

    var currentDuration: TimeInterval {
        TimeInterval(duration(for: phase) * 60)
    }

    var nextPhase: PomodoroPhase {
        phase.next
    }

    var remaining: TimeInterval {
        guard isRunning, let endDate else { return max(0, pausedRemaining) }
        return max(0, endDate.timeIntervalSince(now))
    }

    func start() {
        guard !isRunning else { return }
        completion = nil
        now = Date()
        let remaining = pausedRemaining > 0 ? pausedRemaining : currentDuration
        endDate = Date().addingTimeInterval(remaining)
        isRunning = true
        persist()
    }

    func pause() {
        guard isRunning else { return }
        now = Date()
        pausedRemaining = remaining
        endDate = nil
        isRunning = false
        persist()
    }

    func reset() {
        completion = nil
        isRunning = false
        endDate = nil
        pausedRemaining = currentDuration
        persist()
    }

    func clearCompletion() {
        completion = nil
    }

    func startNextPhase() {
        phase = nextPhase
        completion = nil
        isRunning = false
        endDate = nil
        pausedRemaining = currentDuration
        persist()
        start()
    }

    func skip() {
        phase = phase.next
        completion = nil
        isRunning = false
        endDate = nil
        pausedRemaining = currentDuration
        persist()
    }

    func setDuration(_ minutes: Int, for phase: PomodoroPhase) {
        let value = Self.minutes(minutes, fallback: duration(for: phase))
        switch phase {
        case .focus: focusMinutes = value
        case .shortBreak: shortBreakMinutes = value
        }
        if !isRunning && self.phase == phase { pausedRemaining = currentDuration }
        persist()
    }

    func duration(for phase: PomodoroPhase) -> Int {
        switch phase {
        case .focus: return focusMinutes
        case .shortBreak: return shortBreakMinutes
        }
    }

    private func tick() {
        now = Date()
        guard isRunning, let endDate, endDate <= now else { return }
        isRunning = false
        self.endDate = nil
        pausedRemaining = 0
        if phase == .focus { completedFocusSessions += 1 }
        completion = PomodoroCompletion(phase: phase, completedAt: Date())
        persist()
    }

    private func persist() {
        defaults.set(phase.rawValue, forKey: phaseKey)
        defaults.set(isRunning, forKey: runningKey)
        defaults.set(endDate?.timeIntervalSince1970, forKey: endDateKey)
        defaults.set(pausedRemaining, forKey: remainingKey)
        defaults.set(completedFocusSessions, forKey: completedKey)
        defaults.set(focusMinutes, forKey: focusKey)
        defaults.set(shortBreakMinutes, forKey: shortBreakKey)
    }

    private static func minutes(_ value: Int, fallback: Int) -> Int {
        let value = value == 0 ? fallback : value
        return min(max(value, 1), 120)
    }
}
