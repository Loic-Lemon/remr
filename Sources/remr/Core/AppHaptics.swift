import AppKit

/// The same gentle tap for every user-facing screen presentation.
@MainActor
enum AppHaptics {
    private static var lastOpeningTime: TimeInterval = -.infinity

    static func screenOpened() {
        guard SettingsStore.shared.notchHapticEnabled else { return }
        // A window opening and its initial page can arrive in the same turn.
        // Treat those as a single presentation rather than tapping twice.
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastOpeningTime >= 0.08 else { return }
        lastOpeningTime = now
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }
}
