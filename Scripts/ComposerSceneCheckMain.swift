import AppKit
import ImageIO
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

@testable import remr

/// Captures only this fixture's own window, including the actual native glass
/// compositor. No Screen Recording permission or user's reminders are needed.
private final class SceneCheckPanel: NSWindow {
    override var canBecomeKey: Bool { true }
    // Hold the fixture's key-state steady for capture without activating the
    // app or stealing the user's keyboard. The editor and native compositor
    // are real; only window activity is controlled by this test window.
    override var isKeyWindow: Bool { true }
    override func sendEvent(_ event: NSEvent) {
        // Test input is sent directly to its own editor. Keep any hardware
        // typing during the short capture out of the disposable test field.
        if [.keyDown, .keyUp, .flagsChanged].contains(event.type) { return }
        super.sendEvent(event)
    }
}

private final class OpeningTracker { var count = 0 }

private struct SceneCheckView: View {
    let store: ReminderStore
    let settings: SettingsStore
    let scheme: ColorScheme
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("remr · task field animation check")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(height: 16)
            if reduceMotion {
                // Exercise the same production background with playback off.
                // SwiftUI's system Reduce Motion environment is read-only.
                HStack(spacing: 8) {
                    Image(systemName: "plus").frame(width: 14)
                    ReminderInputView(text: .constant(""))
                        .frame(height: 32)
                }
                .padding(.horizontal, 10).padding(.vertical, 2)
                .background {
                    TaskComposerNightBackground(animates: false)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .liquidGlassInputField(focused: false)
            } else {
                NewReminderView(autofocus: false)
                    .environmentObject(store)
                    .environmentObject(settings)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 568, height: 260, alignment: .topLeading)
        .background(scheme == .dark
                    ? Color(red: 0.12, green: 0.13, blue: 0.16)
                    : Color(red: 0.94, green: 0.95, blue: 0.97))
        .environment(\.colorScheme, scheme)
    }
}

@main
struct ComposerSceneCheckMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                try checkRandomizedScene()
                if #available(macOS 14.4, *) {
                    try await run()
                } else {
                    throw CheckError.message("Own-process Window Server capture requires macOS 14.4 or later")
                }
                print("composer scene checks passed")
                exit(0)
            } catch {
                print("FAIL: \(error)")
                exit(1)
            }
        }
        // A proper AppKit event loop is necessary for genuine key-window and
        // first-responder notifications. RunLoop polling alone misses them.
        app.run()
    }

    private enum CheckError: Error { case message(String) }

    private static func checkRandomizedScene() throws {
        let session = ComposerNightSession(seed: 42)
        let amplitude = CGSize(width: 16, height: 4)
        let first = session.drift(channel: 30, time: 0, amplitude: amplitude)
        let later = session.drift(channel: 30, time: 3, amplitude: amplitude)
        try require(abs(first.x - later.x) > 0.01 && abs(first.y - later.y) > 0.01,
                    "seeded movement wanders on both axes")
        for index in 0..<200 {
            let time = Double(index) * 0.2
            let a = session.drift(channel: 30, time: time, amplitude: amplitude)
            let b = session.drift(channel: 30, time: time + 0.01, amplitude: amplitude)
            guard abs(a.x) <= 16, abs(a.y) <= 4,
                  abs(a.x - b.x) < 0.1, abs(a.y - b.y) < 0.1 else {
                throw CheckError.message("randomized movement must stay bounded and continuous")
            }
        }
        try require(first == ComposerNightSession(seed: 42).drift(channel: 30, time: 0, amplitude: amplitude),
                    "the same presentation seed preserves its path")
        let other = ComposerNightSession(seed: 43).drift(channel: 30, time: 0, amplitude: amplitude)
        try require(other != first, "different openings choose different paths")

        var twinklingStars = 0
        for star in 0..<10 {
            let samples = (0..<900).map { session.starBrightness(index: star, time: Double($0) / 10) }
            guard samples.allSatisfy({ $0 > 0 && $0 <= 1 }) else {
                throw CheckError.message("twinkles must retain a readable star and avoid flashes")
            }
            if samples.max()! - samples.min()! > 0.2 { twinklingStars += 1 }
        }
        try require(twinklingStars > 0 && twinklingStars < 10,
                    "occasional twinkles affect a subset of stars")

        let events = (0..<1024).compactMap { ComposerNightSession(seed: UInt64($0)).shootingStar }
        try require(events.count > 180 && events.count < 330,
                    "shooting stars are a roughly one-in-four opening event")
        let event = events[0]
        try require(event.progress(at: 0) == nil &&
                    event.progress(at: event.delay + event.duration / 2) != nil &&
                    event.progress(at: event.delay + event.duration + 0.1) == nil &&
                    event.progress(at: 100) == nil,
                    "a shooting star appears once after its delay and never repeats")
    }

    @MainActor @available(macOS 14.4, *)
    private static func run() async throws {
        let record = CommandLine.arguments.contains("--record")
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["COMPOSER_SCENE_OUTPUT"]
                         ?? FileManager.default.currentDirectoryPath + "/build/composer-scene", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let suite = "remr.scene-check.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        let store = ReminderStore() // Never started or authorized; cannot write reminders.

        for (name, scheme, reduced) in [("dark", ColorScheme.dark, false),
                                        ("light", ColorScheme.light, false),
                                        ("paused", ColorScheme.dark, true)] {
            let openings = OpeningTracker()
            let host = NSHostingView(rootView: SceneCheckView(store: store, settings: settings,
                                                              scheme: scheme, reduceMotion: reduced)
                .background(ComposerWindowActivity(onChange: { _ in }, onOpen: { openings.count += 1 })))
            let window = SceneCheckPanel(contentRect: NSRect(x: 0, y: 0, width: 568, height: 260),
                                         styleMask: [.titled], backing: .buffered, defer: false)
            window.title = "remr scene check"
            window.contentView = host
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            window.hasShadow = false
            window.center()
            window.orderFrontRegardless()
            defer { window.orderOut(nil) }
            try await pause(0.5)
            try require(openings.count == 1, "\(name): first presentation rolls one scene session")
            let editors = descendants(host).compactMap { $0 as? EnterSubmitTextView }
            guard let editor = editors.first else { throw CheckError.message("\(name): no native editor") }
            let identity = ObjectIdentifier(editor)
            let originalFrame = editor.convert(editor.bounds, to: host)
            print("\(name): controlled window activity, real native first responder")
            guard window.makeFirstResponder(editor), window.isKeyWindow else {
                throw CheckError.message("\(name): fixture did not become key and focused")
            }
            try await pause(0.65)
            let focusedFrame = editor.convert(editor.bounds, to: host)
            print("\(name): native editor bounds before=\(originalFrame), focused=\(focusedFrame)")
            try require(abs(focusedFrame.minX - originalFrame.minX) < 0.3 &&
                        abs(focusedFrame.minY - originalFrame.minY) < 0.3 &&
                        abs(focusedFrame.width - originalFrame.width) < 0.3 &&
                        abs(focusedFrame.height - originalFrame.height) < 0.3,
                        "\(name): focusing keeps the native text geometry stationary")

            let content = try await SCShareableContent.currentProcess
            guard let ownWindow = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
                throw CheckError.message("\(name): own window unavailable for capture")
            }
            let filter = SCContentFilter(desktopIndependentWindow: ownWindow)
            let config = SCStreamConfiguration()
            config.width = 1136; config.height = Int(window.frame.height * 2)
            config.showsCursor = false
            config.ignoreShadowsSingleWindow = true
            func capture() async throws -> CGImage {
                try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            }
            let first = try await capture()
            try save(first, to: output.appendingPathComponent("\(name)-start.png"))
            try await pause(3)
            let second = try await capture()
            try save(second, to: output.appendingPathComponent("\(name)-after-3s.png"))
            // Right-hand sky, away from the caret and text. The actual field
            // starts at (24, 56), and the native capture is at 2x scale.
            let titleHeight = window.frame.height - host.frame.height
            let motion = difference(first, second, rect: CGRect(x: 560, y: (60 + titleHeight) * 2, width: 280, height: 56))
            print("\(name): sky pixel change after 3s = \(String(format: "%.5f", motion))")
            // Detect a stopped clock without requiring every randomized path
            // to move at the same speed during this short sample.
            try require(reduced ? motion < 0.001 : (motion > 0.001 && motion < 0.08),
                        "\(name): \(reduced ? "disabling playback freezes the sky" : "the integrated sky advances")")
            try require(descendants(host).compactMap { $0 as? EnterSubmitTextView }
                        .first.map(ObjectIdentifier.init) == identity,
                        "\(name): animation retains the native editor")

            if record && !reduced {
                let gifURL = output.appendingPathComponent("\(name).gif")
                guard let destination = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, 144, nil) else {
                    throw CheckError.message("Cannot create recording")
                }
                CGImageDestinationSetProperties(destination,
                    [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
                let start = Date()
                for index in 0..<144 {
                    if index == 60 {
                        editor.insertText("Plan tomorrow", replacementRange: NSRange(location: NSNotFound, length: 0))
                    }
                    if index == 96 { editor.insertNewline(nil) }
                    let target = start.addingTimeInterval(Double(index) / 12)
                    let wait = target.timeIntervalSinceNow
                    if wait > 0 { try await pause(wait) }
                    let image = try await capture()
                    CGImageDestinationAddImage(destination, image,
                        [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / 12]] as CFDictionary)
                }
                guard CGImageDestinationFinalize(destination) else { throw CheckError.message("Recording failed") }
                print("Native-window recording: \(gifURL.path)")
            }
            window.makeFirstResponder(nil)
            try await pause(0.4)
            try require(!(window.firstResponder is EnterSubmitTextView), "\(name): blur releases editing")
            NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
            window.makeFirstResponder(editor)
            try await pause(0.1)
            try require(openings.count == 1, "\(name): refocusing does not reroll the shooting-star chance")
            window.orderOut(nil)
            try await pause(0.15)
            window.orderFrontRegardless()
            try await pause(0.15)
            try require(openings.count == 2, "\(name): reopening rolls a fresh scene session")
            window.orderOut(nil)
        }
    }

    private static func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private static func pause(_ seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw CheckError.message(message) }
        print("PASS: \(message)")
    }

    private static func save(_ image: CGImage, to url: URL) throws {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CheckError.message("Cannot encode snapshot")
        }
        try data.write(to: url)
    }

    private static func difference(_ first: CGImage, _ second: CGImage, rect: CGRect) -> Double {
        guard let a = first.cropping(to: rect), let b = second.cropping(to: rect) else { return -1 }
        let width = a.width, height = a.height
        func pixels(_ image: CGImage) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            bytes.withUnsafeMutableBytes { buffer in
                let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                        bitsPerComponent: 8, bytesPerRow: width * 4,
                                        space: CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            return bytes
        }
        let aPixels = pixels(a), bPixels = pixels(b)
        var sum = 0
        for offset in stride(from: 0, to: aPixels.count, by: 4) {
            for channel in 0..<3 { sum += abs(Int(aPixels[offset + channel]) - Int(bPixels[offset + channel])) }
        }
        return Double(sum) / Double(width * height * 3 * 255)
    }
}
