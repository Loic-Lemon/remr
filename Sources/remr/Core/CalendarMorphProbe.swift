import AppKit

/// Temporary runtime probe for the calendar morph handoff. Inert unless
/// REMR_MORPH_PROBE is set in the environment. Remove with its call sites,
/// marked REMR-MORPH-PROBE-BEGIN/END in AppDelegate.
///
/// It opens the reminders panel, calls `showCalendar()` exactly as the C key
/// does, and samples the calendar view's painted shape over time so the real
/// app's morph start can be read from /tmp/remr-morph-probe.log.
enum CalendarMorphProbe {
    static let logURL = URL(fileURLWithPath: "/tmp/remr-morph-probe.log")

    nonisolated static var enabled: Bool { ProcessInfo.processInfo.environment["REMR_MORPH_PROBE"] != nil }

    nonisolated static func log(_ message: String) {
        guard enabled else { return }
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
    static func startIfRequested() {
        guard enabled else { return }
        try? "".write(to: logURL, atomically: true, encoding: .utf8)
        log("probe start")
        after(1.0) {
            log("warming calendar hidden render")
            AppDelegate.instance?.probeWarmCalendar()
            log("warm done")
        }
        after(2.5) {
            log("opening main surface")
            AppDelegate.instance?.probeShowMainSurface()
        }
        after(3.8) {
            guard let app = AppDelegate.instance else { return }
            let notch = app.probeNotchWindow
            log("before showCalendar notchVisible=\(notch?.isVisible ?? false) notchSize=\(Self.size(notch)) notchAlpha=\(Self.alpha(notch))")
            log("calling showCalendar")
            startBlockTicker()
            app.showCalendar()
            sample(app, tag: "t=0.00")
            after(0.02) { log("alpha t=0.02 notchAlpha=\(alpha(app.probeNotchWindow))") }
            after(0.06) { log("alpha t=0.06 notchAlpha=\(alpha(app.probeNotchWindow))") }
            after(0.10) { log("alpha t=0.10 notchAlpha=\(alpha(app.probeNotchWindow))") }
            after(0.16) { log("alpha t=0.16 notchAlpha=\(alpha(app.probeNotchWindow))") }
            after(0.24) { log("alpha t=0.24 notchAlpha=\(alpha(app.probeNotchWindow))") }
            after(0.03) { sample(app, tag: "t=0.03") }
            after(0.09) { sample(app, tag: "t=0.09") }
            after(0.18) { sample(app, tag: "t=0.18") }
            after(0.45) { sample(app, tag: "t=0.45") }
            after(1.0) { log("probe done") }
        }
    }

    @MainActor
    private static func sample(_ app: AppDelegate, tag: String) {
        let shape = measure(app.probeCalendarHosting)
        let cal = app.probeCalendarWindow
        let notch = app.probeNotchWindow
        let reveal = app.probeCalendarReveal
        log("\(tag) calendarShape=\(shape.map { "\(Int($0.w))x\(Int($0.h))" } ?? "nil") calVisible=\(cal?.isVisible ?? false) calAlpha=\(alpha(cal)) notchVisible=\(notch?.isVisible ?? false) notchAlpha=\(alpha(notch)) flags(w=\(reveal.widthRevealed) h=\(reveal.heightRevealed) c=\(reveal.contentRevealed))")
    }

    /// Logs when the main thread stalls longer than a few milliseconds, so
    /// the reveal's wall-clock behaviour can be separated from real jank.
    @MainActor
    private static func startBlockTicker() {
        Task { @MainActor in
            let start = Date()
            var next = 0.0
            while Date().timeIntervalSince(start) < 1.6 {
                let target = start.addingTimeInterval(next)
                next += 0.01
                let lateness = Date().timeIntervalSince(target)
                if lateness > 0.04 {
                    log(String(format: "block: main thread busy ~%.0fms before t=%.2f", lateness * 1000, next))
                }
                if lateness < 0.01 {
                    try? await Task.sleep(nanoseconds: 10_000_000)
                }
            }
            log("block ticker done")
        }
    }

    @MainActor
    private static func size(_ window: NSWindow?) -> String {
        guard let frame = window?.frame else { return "nil" }
        return "\(Int(frame.width))x\(Int(frame.height))@\(Int(frame.minX)),\(Int(frame.minY))"
    }

    @MainActor
    private static func alpha(_ window: NSWindow?) -> String {
        guard let window else { return "nil" }
        return String(format: "%.2f", window.alphaValue)
    }

    @MainActor
    private static func measure(_ view: NSView?) -> (w: CGFloat, h: CGFloat)? {
        guard let view else { return nil }
        let bounds = view.bounds
        let pw = Int(bounds.width), ph = Int(bounds.height)
        guard pw > 0, ph > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pw, pixelsHigh: ph,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 32) else { return nil }
        view.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.bitmapData else { return nil }
        let stride = rep.bytesPerRow
        var minX = pw, minY = ph, maxX = -1, maxY = -1
        for y in Swift.stride(from: 0, to: ph, by: 2) {
            let row = data + y * stride
            for x in Swift.stride(from: 0, to: pw, by: 2) where row[x * 4 + 3] > 30 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return (CGFloat(maxX - minX + 1), CGFloat(maxY - minY + 1))
    }

    @MainActor
    private static func after(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            work()
        }
    }
}
