import AppKit
import SwiftUI

@testable import remr

/// Renders the calendar's reveal in a real window and measures the shape it
/// paints over time, mirroring `showCalendar`'s exact sequence. This is the
/// only way to observe the geometry SwiftUI actually commits at each frame,
/// which is where the morph either starts from the reminders panel or falls
/// back to the collapsed notch strip.
///
/// Two scenarios run: the calendar window already visible (a fresh launch's
/// first presentation) and the calendar window hidden until the order-front
/// inside `showCalendar` (every presentation after a close). The hidden case
/// is the real one: SwiftUI defers updates for hidden hosting views, so the
/// morph start must survive losing the race to the async `open()`.
@main
struct MorphCheckMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        var failures = 0
        func fail(_ message: String) {
            failures += 1
            print("FAIL: \(message)")
        }
        func advance(_ seconds: TimeInterval) {
            RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        }
        func runScenario(_ name: String, hiddenStart: Bool) {
            print("scenario: \(name)")
            let width: CGFloat = 1084
            let height: CGFloat = 932
            let inset: CGFloat = 33
            let panelSize = CGSize(width: 580, height: 630)
            let controller = NotchRevealController(duration: 0.22, contentFadeDuration: 0.08)

            let root = Rectangle().fill(Color.red)
                .frame(width: width - 28, height: height - inset)
                .notchContentReveal(controller)
                .padding(.top, inset)
                .padding(.horizontal, 14)
                .notchReveal(controller, collapsedWidth: 172, collapsedHeight: inset,
                             surface: Color.black, backdrop: Color.clear)

            let hosting = NSHostingView(rootView: root)
            hosting.sizingOptions = []
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.alphaValue = 0.02
            window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            if let screen = NSScreen.main {
                window.setFrameTopLeftPoint(NSPoint(x: screen.frame.midX - width / 2, y: screen.frame.maxY))
            }
            window.orderFrontRegardless()

            if hiddenStart {
                // Leave the window in the state a real close leaves behind:
                // the collapse fully committed, then the window ordered out.
                controller.open(animated: false)
                advance(0.05)
                controller.retract()
                advance(0.5)
                window.orderOut(nil)
                advance(0.05)
            }

            func report(_ condition: Bool, _ message: String) {
                if condition {
                    print("PASS: \(message)")
                } else {
                    fail("\(name): \(message)")
                }
            }
            func measuredShape() -> (w: CGFloat, h: CGFloat)? {
                let bounds = hosting.bounds
                let pw = Int(bounds.width), ph = Int(bounds.height)
                guard pw > 0, ph > 0,
                      let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pw, pixelsHigh: ph,
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                 isPlanar: false, colorSpaceName: .deviceRGB,
                                                 bytesPerRow: 0, bitsPerPixel: 32) else { return nil }
                hosting.cacheDisplay(in: bounds, to: rep)
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
            func probe(_ label: String) -> (w: CGFloat, h: CGFloat)? {
                let shape = measuredShape()
                if let shape {
                    print("  [\(label)] shape ≈ \(Int(shape.w))×\(Int(shape.h))")
                } else {
                    print("  [\(label)] no opaque pixels")
                }
                return shape
            }

            // Mirror showCalendar: the start size is set while the window is
            // hidden, the window is ordered front, then open() runs on the
            // next main-queue turn.
            controller.reset()
            controller.startSize = panelSize
            hosting.layoutSubtreeIfNeeded()
            window.orderFrontRegardless()
            DispatchQueue.main.async { controller.open(animated: true) }

            advance(0.005)
            let first = probe("first frame after open")
            advance(0.05)
            let early = probe("early")
            advance(0.30)
            let settled = probe("settled")

            if let first {
                // The eased curve front-loads hard, so a probe landing a few
                // milliseconds late already reads tens of pixels wide. The
                // tolerance is wide enough for that latency and still far
                // below the collapsed strip (~172) this must not start from.
                report(abs(first.w - panelSize.width) <= 100,
                       "The first frame starts at the panel silhouette width (\(Int(first.w)) vs \(Int(panelSize.width)))")
                report(abs(first.h - panelSize.height) <= 60,
                       "The first frame starts at the panel silhouette height (\(Int(first.h)) vs \(Int(panelSize.height)))")
            } else {
                report(false, "The revealed shape renders at all")
            }
            if let first, let early {
                report(early.w >= first.w - 2, "The silhouette expands past the panel width")
            }
            if let settled {
                report(abs(settled.w - width) <= 20 && abs(settled.h - height) <= 20,
                       "The silhouette settles at the full calendar size (\(Int(settled.w))×\(Int(settled.h)))")
            }
            window.orderOut(nil)
        }

        runScenario("visible window", hiddenStart: false)
        runScenario("hidden window (state after a close)", hiddenStart: true)

        print(failures == 0 ? "morph checks passed" : "\(failures) morph check(s) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
