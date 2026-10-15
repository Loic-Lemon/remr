import AppKit

/// Temporary runtime probe for the Pomodoro keyboard pipeline. Inert unless
/// REMR_POMO_PROBE is set in the environment. Remove with its call sites,
/// marked REMR-POMO-PROBE-BEGIN/END in AppDelegate and MainView.
enum PomodoroKeyProbe {
    static let logURL = URL(fileURLWithPath: "/tmp/remr-pomodoro-key-probe.log")

    nonisolated static var enabled: Bool { ProcessInfo.processInfo.environment["REMR_POMO_PROBE"] != nil }

    /// Logging is armed by a marker file so a normal user launch (no env) can
    /// still capture the pipeline without the synthetic-key driver.
    nonisolated static var loggingEnabled: Bool {
        enabled || FileManager.default.fileExists(atPath: "/tmp/remr-pomodoro-key-probe.armed")
    }

    nonisolated static func log(_ message: String) {
        guard loggingEnabled else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let line = "\(formatter.string(from: Date())) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: logURL, atomically: true, encoding: .utf8)
        }
    }

    @MainActor
    static func startDriverIfRequested() {
        guard enabled else { return }
        try? "".write(to: logURL, atomically: true, encoding: .utf8)
        log("driver:start notchPopover=\(SettingsStore.shared.notchPopover) pomodoroEnabled=\(SettingsStore.shared.pomodoroEnabled)")

        after(2.0) { @MainActor in
            log("driver:open main surface")
            AppDelegate.instance?.probeShowMainSurface()
        }
        after(3.5) { @MainActor in postKey(35, "p", label: "P1") }
        after(5.0) { @MainActor in postKey(35, "p", label: "P2") }
        after(6.5) { @MainActor in postKey(35, "p", label: "P3") }
        after(8.0) { @MainActor in postKey(36, "\r", label: "Enter1") }
        after(9.0) { @MainActor in postKey(36, "\r", label: "Enter2") }
        after(10.5) { @MainActor in log("driver:done \(AppDelegate.instance?.probeMainSurfaceState ?? "?")") }
    }

    @MainActor
    private static func after(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            work()
        }
    }

    @MainActor
    private static func postKey(_ keyCode: UInt16, _ characters: String, label: String) {
        guard let window = NSApp.keyWindow else {
            log("driver:\(label) no key window")
            return
        }
        log("driver:\(label) keyWindow=#\(window.windowNumber) \(type(of: window)) active=\(NSApp.isActive) \(AppDelegate.instance?.probeMainSurfaceState ?? "?")")
        for type in [NSEvent.EventType.keyDown, NSEvent.EventType.keyUp] {
            guard let event = NSEvent.keyEvent(with: type,
                                               location: .zero,
                                               modifierFlags: [],
                                               timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: window.windowNumber,
                                               context: nil,
                                               characters: characters,
                                               charactersIgnoringModifiers: characters,
                                               isARepeat: false,
                                               keyCode: keyCode) else { continue }
            NSApp.postEvent(event, atStart: false)
        }
    }
}
