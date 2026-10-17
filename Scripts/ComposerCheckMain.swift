import AppKit
import SwiftUI

@testable import remr

private struct ComposerProbe: View {
    let store: ReminderStore
    let settings: SettingsStore
    var body: some View {
        NewReminderView(autofocus: false)
            .environmentObject(store)
            .environmentObject(settings)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ControlGateProbe: NSViewRepresentable {
    @Environment(\.nativeControlGlassEnabled) private var enabled
    let report: (Bool) -> Void
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }
    func updateNSView(_ view: NSView, context: Context) { report(enabled) }
}

@main
struct ComposerCheckMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let suiteName = "remr.composer-check.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ReminderStore() // Deliberately never started or authorized.
        let settings = SettingsStore(defaults: defaults)
        var failures = 0
        func check(_ condition: Bool, _ message: String) {
            print("\(condition ? "PASS" : "FAIL"): \(message)")
            if !condition { failures += 1 }
        }
        func advance(_ seconds: TimeInterval) {
            RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        }
        func descendants(_ view: NSView) -> [NSView] {
            view.subviews.flatMap { [$0] + descendants($0) }
        }

        for width: CGFloat in [350, 800] {
            let reader = NSHostingView(rootView: ComposerProbe(store: store, settings: settings)
                .frame(width: width))
            reader.sizingOptions = [.intrinsicContentSize]
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 180),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = reader
            window.center()
            window.makeKeyAndOrderFront(nil)
            app.activate(ignoringOtherApps: true)
            reader.layoutSubtreeIfNeeded()
            reader.displayIfNeeded()
            advance(0.15)
            reader.layoutSubtreeIfNeeded()
            reader.displayIfNeeded()

            let editor = descendants(reader).compactMap { $0 as? EnterSubmitTextView }.first
            check(editor != nil, "\(Int(width))pt editor contains the native EnterSubmitTextView")
            guard let editor else { window.orderOut(nil); continue }
            let original = ObjectIdentifier(editor)
            let originalFrame = editor.convert(editor.bounds, to: reader)
            let idleSize = reader.intrinsicContentSize
            let idleHeight = idleSize.height
            check(abs(idleHeight - 36) <= 1.5,
                  "\(Int(width))pt empty composer is 36pt tall (measured \(idleHeight))")
            check(abs(idleSize.width - width) <= 1,
                  "\(Int(width))pt composer uses the available width (measured \(idleSize.width))")

            check(window.makeFirstResponder(editor), "native editor becomes first responder")
            advance(0.12)
            let focusedHeight = reader.intrinsicContentSize.height
            let focusedEditor = descendants(reader).compactMap { $0 as? EnterSubmitTextView }.first
            check(focusedEditor.map(ObjectIdentifier.init) == original,
                  "focus keeps the same native editor instance")
            check(abs(focusedHeight - idleHeight) <= 1.5,
                  "focus preserves composer bounds (\(idleHeight)pt → \(focusedHeight)pt)")
            check(editor.convert(editor.bounds, to: reader) == originalFrame,
                  "focus leaves native text geometry stationary")

            window.makeFirstResponder(nil)
            advance(0.12)
            check(abs(reader.intrinsicContentSize.height - idleHeight) <= 1.5,
                  "blur restores the same composer bounds")
            check(descendants(reader).compactMap { $0 as? EnterSubmitTextView }
                      .first.map(ObjectIdentifier.init) == original,
                  "blur keeps the same native editor instance")
            check(!(window.firstResponder is EnterSubmitTextView), "blur leaves the editor for browsing shortcuts")

            window.makeFirstResponder(editor)
            editor.insertText("Plan tomorrow", replacementRange: NSRange(location: NSNotFound, length: 0))
            advance(0.40)
            let fields = descendants(reader).compactMap { $0 as? EnterSubmitTextView }
            check(fields.count == 2 && reader.intrinsicContentSize.height > idleHeight + 20,
                  "typing still expands the notes and parsed preview naturally")
            check(fields.contains { ObjectIdentifier($0) == original },
                  "content expansion retains the title editor")
            editor.insertNewline(nil)
            advance(0.10)
            check((window.firstResponder as? EnterSubmitTextView).map { $0 !== editor && !$0.movesDownOnReturn } == true,
                  "Return still moves from title into notes without submitting")
            window.orderOut(nil)
        }

        let reveal = NotchRevealController(duration: 0.12, contentFadeDuration: 0.03)
        reveal.open(animated: true)
        check(!reveal.contentRevealed, "reveal keeps content hidden during the opening delay")
        advance(0.04)
        check(!reveal.contentRevealed, "content remains hidden before the panel opening finishes")
        reveal.reset()
        advance(0.14)
        check(!reveal.widthRevealed && !reveal.heightRevealed && !reveal.contentRevealed,
              "reset cancels delayed callbacks from an interrupted open")
        reveal.open(animated: true)
        advance(0.18)
        check(reveal.widthRevealed && reveal.heightRevealed && reveal.contentRevealed,
              "a fresh open reveals the silhouette and content")
        reveal.retract()
        advance(0.02)
        reveal.open(animated: true)
        advance(0.18)
        check(reveal.contentRevealed, "a rapid reopen survives stale callbacks from the prior close")

        runQuickAddFixture(settings: settings, store: store, app: app, check: check, advance: advance)

        runMainViewFixture(settings: settings, store: store, app: app, check: check, advance: advance)

        print(failures == 0 ? "composer checks passed" : "\(failures) composer check(s) failed")
        exit(failures == 0 ? 0 : 1)
    }

    @MainActor
    private static func runQuickAddFixture(settings: SettingsStore,
                                           store: ReminderStore,
                                           app: NSApplication,
                                           check: (Bool, String) -> Void,
                                           advance: (TimeInterval) -> Void) {
        var measuredHeight: CGFloat = 0
        let host = NSHostingView(rootView: QuickAddSurface(onHeightChange: { measuredHeight = $0 }) {
            NewReminderView(autofocus: false)
                .environmentObject(store)
                .environmentObject(settings)
        })
        host.sizingOptions = [.intrinsicContentSize]
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: QuickAddView.width, height: 60),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        advance(0.15)
        host.layoutSubtreeIfNeeded()
        let collapsed = host.fittingSize.height
        check(abs(collapsed - 60) < 1, "quick-add fits the 36pt task bar plus 12pt padding per side")
        check(abs(measuredHeight - collapsed) < 1, "quick-add reports its natural height to the panel")

        func editors(_ view: NSView) -> [EnterSubmitTextView] {
            view.subviews.flatMap { child in
                ((child as? EnterSubmitTextView).map { [$0] } ?? []) + editors(child)
            }
        }
        guard let title = editors(host).first else {
            check(false, "quick-add contains a native title editor")
            window.orderOut(nil)
            return
        }
        window.makeFirstResponder(title)
        title.insertText("Plan tomorrow", replacementRange: NSRange(location: NSNotFound, length: 0))
        advance(0.45)
        host.layoutSubtreeIfNeeded()
        let expanded = host.fittingSize.height
        check(expanded > collapsed + 30, "quick-add grows with description and parsed preview")
        check(abs(measuredHeight - expanded) < 1, "panel height follows the expanded composer")
        check(abs(host.fittingSize.width - QuickAddView.width) < 1, "quick-add keeps its wider width when expanding")
        title.insertText("", replacementRange: NSRange(location: 0, length: title.string.utf16.count))
        advance(0.45)
        host.layoutSubtreeIfNeeded()
        check(abs(host.fittingSize.height - collapsed) < 1 && abs(measuredHeight - collapsed) < 1,
              "clearing the task collapses the popup back to the padded text bar")
        check(editors(host).first === title, "popup resizing retains the native title editor")
        window.orderOut(nil)
    }

    @MainActor
    private static func runMainViewFixture(settings: SettingsStore,
                                          store: ReminderStore,
                                          app: NSApplication,
                                          check: (Bool, String) -> Void,
                                          advance: (TimeInterval) -> Void) {
        settings.setNotchPopover(true)
        let reveal = NotchRevealController(duration: 0.14, contentFadeDuration: 0.04)
        var controlGate: Bool?
        let root = MainView(surface: .floatingPanel)
            .environmentObject(store)
            .environmentObject(settings)
            .environmentObject(VoiceLogStore.shared)
            .background(ControlGateProbe { controlGate = $0 })
            .frame(width: 772, height: 600)
            .notchContentReveal(reveal)
            .padding(.top, 32)
            .padding(.horizontal, 14)
            .notchReveal(reveal, collapsedWidth: 172, collapsedHeight: 32,
                         surface: Color.clear, backdrop: Color.clear)
            .frame(width: 800, height: 632)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 632),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.center()
        reveal.reset()
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        host.layoutSubtreeIfNeeded()
        advance(0.12)

        func searchFields() -> [NSTextField] {
            func descend(_ view: NSView) -> [NSTextField] {
                view.subviews.flatMap { child in
                    let match = (child as? NSTextField).flatMap {
                        $0.placeholderString == "Search reminders" ? [$0] : nil
                    } ?? []
                    return match + descend(child)
                }
            }
            return descend(host)
        }
        let before = searchFields().first
        check(before != nil, "MainView fixture exposes its native Search text field")
        guard let before else { window.orderOut(nil); return }
        let identity = ObjectIdentifier(before)
        let initialFrame = before.convert(before.bounds, to: host)
        check(!reveal.contentRevealed, "MainView fixture begins with foreground content hidden")
        check(controlGate == false, "MainView disables native control glass before the foreground reveal")

        reveal.open(animated: true)
        advance(0.24)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let after = searchFields().first
        check(after.map(ObjectIdentifier.init) == identity,
              "Search keeps the same native text field across the reveal gate")
        if let after {
            let settledFrame = after.convert(after.bounds, to: host)
            check(abs(settledFrame.minX - initialFrame.minX) < 1 &&
                  abs(settledFrame.minY - initialFrame.minY) < 1 &&
                  abs(settledFrame.width - initialFrame.width) < 1 &&
                  abs(settledFrame.height - initialFrame.height) < 1,
                  "Search bounds remain stable across reveal (\(settledFrame))")
        }
        check(reveal.contentRevealed && controlGate == true,
              "MainView foreground and native control gate open together")

        window.orderOut(nil)
        reveal.reset()
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        window.makeKeyAndOrderFront(nil)
        advance(0.03)
        check(controlGate == false, "a retained panel reopens with native control glass disabled")
        reveal.open(animated: true)
        advance(0.24)
        check(controlGate == true && searchFields().first.map(ObjectIdentifier.init) == identity,
              "a retained panel reveals the same Search control again")

        if let path = ProcessInfo.processInfo.environment["COMPOSER_CHECK_SNAPSHOT"] {
            let bounds = host.bounds
            let pixelsWide = max(1, Int(bounds.width * window.backingScaleFactor))
            let pixelsHigh = max(1, Int(bounds.height * window.backingScaleFactor))
            if let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide,
                                          pixelsHigh: pixelsHigh, bitsPerSample: 8,
                                          samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                          colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32) {
                rep.size = bounds.size
                host.cacheDisplay(in: bounds, to: rep)
                if let data = rep.representation(using: .png, properties: [:]) {
                    do {
                        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
                        print("debug AppKit cache snapshot (not a Window Server capture): \(path)")
                    } catch { print("snapshot failed: \(error)") }
                }
            }
        }
        window.orderOut(nil)
    }
}
