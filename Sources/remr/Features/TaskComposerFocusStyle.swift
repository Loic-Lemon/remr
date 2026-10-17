import AppKit
import SwiftUI

/// Grow the complete decorative shell while keeping the native editor and
/// the composer's layout footprint stationary.
struct TaskComposerFocusStyle: ViewModifier {
    let isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.nativeControlGlassEnabled) private var contentVisible
    @State private var windowActive = false
    @State private var session = ComposerNightSession.preview

    private var editing: Bool { isFocused && windowActive && contentVisible }
    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    func body(content: Content) -> some View {
        let horizontalGrowth: CGFloat = editing && !reduceMotion ? 4 : 0
        let verticalGrowth: CGFloat = editing && !reduceMotion ? 2 : 0

        content
            // Expand the lens itself, so its native rim and focus treatment
            // share one boundary instead of leaving an inner glass rectangle.
            .padding(.horizontal, horizontalGrowth)
            .padding(.vertical, verticalGrowth)
            .background {
                TaskComposerNightBackground(animates: editing && !reduceMotion, session: session)
                    .id(session.seed)
                    .clipShape(shape)
                    .opacity(editing ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            // The scene is foreground content of the lens. Placing it after
            // this modifier makes native glass blur away the stars and clouds.
            .liquidGlassInputField(focused: false)
            .overlay {
                shape.strokeBorder(Color.accentColor.opacity(editing ? 0.65 : 0), lineWidth: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            // Cancel the shell's extra layout space. Text, caret, Search,
            // and Tags retain their original positions throughout the spring.
            .padding(.horizontal, -horizontalGrowth)
            .padding(.vertical, -verticalGrowth)
            .animation(reduceMotion ? .easeOut(duration: 0.20)
                       : .spring(response: 0.34, dampingFraction: 0.82), value: editing)
            .background(ComposerWindowActivity(onChange: { windowActive = $0 },
                                                onOpen: { session = .random() }))
    }
}

/// Time only advances while visible and editing. Freezing the phase on blur
/// also keeps the fading sky from jumping back to its first frame.
struct TaskComposerNightBackground: View {
    let animates: Bool
    var session: ComposerNightSession = .preview
    @Environment(\.colorScheme) private var colorScheme
    @State private var elapsed: TimeInterval = 0
    @State private var runningSince: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animates)) { context in
            let time = elapsed + (runningSince.map { max(0, context.date.timeIntervalSince($0)) } ?? 0)
            TaskComposerNightScene(time: time, colorScheme: colorScheme, session: session)
        }
        .onAppear { updateClock(isRunning: animates) }
        // Use the delivered value: this callback can retain the previous
        // view's `animates`, leaving the clock stopped after focus changes.
        .onChange(of: animates) { isRunning in updateClock(isRunning: isRunning) }
        .onDisappear { updateClock(isRunning: false) }
    }

    private func updateClock(isRunning: Bool) {
        if isRunning {
            if runningSince == nil { runningSince = Date() }
        } else if let start = runningSince {
            elapsed += Date().timeIntervalSince(start)
            runningSince = nil
        }
    }
}

/// One decorative canvas, above the field material and below native text.
/// Moon, clouds, and stars use independent, continuous motion with stable seeds.
struct TaskComposerNightScene: View {
    let time: TimeInterval
    let colorScheme: ColorScheme
    var session: ComposerNightSession = .preview

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let dark = colorScheme == .dark
            drawSky(context: &context, size: size, dark: dark)
            drawStars(context: &context, size: size, dark: dark)
            drawShootingStar(context: &context, size: size, dark: dark)
            drawMoon(context: &context, size: size, dark: dark)
            drawClouds(context: &context, size: size, dark: dark)
        }
    }

    private func drawSky(context: inout GraphicsContext, size: CGSize, dark: Bool) {
        let rect = Path(CGRect(origin: .zero, size: size))
        let sky: [Color] = dark
            ? [Color(red: 0.11, green: 0.10, blue: 0.23),
               Color(red: 0.08, green: 0.14, blue: 0.27),
               Color(red: 0.055, green: 0.09, blue: 0.18)]
            : [Color(red: 0.89, green: 0.88, blue: 0.96),
               Color(red: 0.83, green: 0.90, blue: 0.98),
               Color(red: 0.93, green: 0.95, blue: 0.99)]
        let flow = time * .pi * 2 / 32
        context.fill(rect, with: .linearGradient(Gradient(colors: sky),
                     startPoint: CGPoint(x: size.width * (-0.10 + CGFloat(sin(flow)) * 0.10), y: 0),
                     endPoint: CGPoint(x: size.width * (1 + CGFloat(cos(flow)) * 0.10), y: size.height)))

        // Translate broad pools of color. Their movement is visible even in
        // the 40-point focused bar, rather than just when notes are expanded.
        let blueDrift = session.drift(channel: 1, time: time,
                                      amplitude: CGSize(width: size.width * 0.18, height: min(24, size.height * 0.45)))
        let violetDrift = session.drift(channel: 2, time: time,
                                        amplitude: CGSize(width: size.width * 0.16, height: min(22, size.height * 0.4)))
        let pools: [(x: CGFloat, y: CGFloat, radius: CGFloat, color: Color)] = [
            (size.width * 0.57 + blueDrift.x,
             size.height * 0.1 + blueDrift.y, size.width * 0.39,
             Color(red: 0.38, green: 0.59, blue: 0.91).opacity(dark ? 0.40 : 0.20)),
            (size.width * 0.28 + violetDrift.x,
             size.height * 1.05 + violetDrift.y, size.width * 0.34,
             Color(red: 0.57, green: 0.39, blue: 0.83).opacity(dark ? 0.29 : 0.17))
        ]
        for pool in pools {
            context.fill(rect, with: .radialGradient(Gradient(colors: [pool.color, .clear]),
                         center: CGPoint(x: pool.x, y: pool.y), startRadius: 0, endRadius: pool.radius))
        }
    }

    private func drawStars(context: inout GraphicsContext, size: CGSize, dark: Bool) {
        for (index, star) in Self.stars.enumerated() {
            let brightness = session.starBrightness(index: index, time: time)
            let drift = session.drift(channel: index + 10, time: time,
                                      amplitude: CGSize(width: 3, height: 1.8), rate: 1.4)
            let radius: CGFloat = index.isMultiple(of: 3) ? 1.35 : 1.05
            let point = CGPoint(
                x: star.x * size.width + drift.x,
                y: star.y * size.height + drift.y)
            let light = dark ? Color(red: 0.88, green: 0.94, blue: 1)
                             : Color(red: 0.30, green: 0.35, blue: 0.64)
            let haloRadius = radius * 3.4
            context.fill(Path(ellipseIn: CGRect(x: point.x - haloRadius, y: point.y - haloRadius,
                                               width: haloRadius * 2, height: haloRadius * 2)),
                         with: .radialGradient(Gradient(colors: [light.opacity(brightness * 0.20), .clear]),
                                               center: point, startRadius: 0, endRadius: haloRadius))
            context.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                                               width: radius * 2, height: radius * 2)),
                         with: .color(light.opacity(brightness * (dark ? 0.95 : 0.78))))
            if index.isMultiple(of: 4) {
                var glint = Path()
                glint.move(to: CGPoint(x: point.x - 3, y: point.y))
                glint.addLine(to: CGPoint(x: point.x + 3, y: point.y))
                glint.move(to: CGPoint(x: point.x, y: point.y - 3))
                glint.addLine(to: CGPoint(x: point.x, y: point.y + 3))
                context.stroke(glint, with: .color(light.opacity(brightness * 0.26)), lineWidth: 0.6)
            }
        }
    }

    private func drawShootingStar(context: inout GraphicsContext, size: CGSize, dark: Bool) {
        guard let event = session.shootingStar, let progress = event.progress(at: time) else { return }
        let start = CGPoint(x: event.start.x * size.width, y: event.start.y * size.height)
        let end = CGPoint(x: event.end.x * size.width, y: event.end.y * size.height)
        let delta = CGPoint(x: end.x - start.x, y: end.y - start.y)
        let distance = max(1, hypot(delta.x, delta.y))
        let head = CGPoint(x: start.x + delta.x * progress, y: start.y + delta.y * progress)
        let length = min(28, size.width * 0.065) * min(1, progress * 5)
        let tail = CGPoint(x: head.x - delta.x / distance * length,
                           y: head.y - delta.y / distance * length)
        let opacity = pow(sin(progress * .pi), 2) * (dark ? 0.65 : 0.45)
        let light = dark ? Color(red: 0.88, green: 0.95, blue: 1) : Color.indigo
        var trail = Path()
        trail.move(to: tail)
        trail.addLine(to: head)
        context.stroke(trail, with: .linearGradient(Gradient(colors: [.clear, light.opacity(opacity)]),
                       startPoint: tail, endPoint: head), style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
        context.fill(Path(ellipseIn: CGRect(x: head.x - 0.8, y: head.y - 0.8, width: 1.6, height: 1.6)),
                     with: .color(light.opacity(opacity)))
    }

    private func drawMoon(context: inout GraphicsContext, size: CGSize, dark: Bool) {
        // The rim extends past the top/right of the field. Its geometry does
        // not change with the notes' height or with each keystroke.
        let radius = min(76, max(55, size.width * 0.14))
        let center = CGPoint(x: size.width * 0.96, y: 12)
        let glow = dark ? Color(red: 0.78, green: 0.84, blue: 1)
                        : Color(red: 0.53, green: 0.58, blue: 0.80)
        let haloRadius = radius * 1.7
        context.fill(Path(ellipseIn: CGRect(x: center.x - haloRadius, y: center.y - haloRadius,
                                           width: haloRadius * 2, height: haloRadius * 2)),
                     with: .radialGradient(Gradient(colors: [glow.opacity(dark ? 0.19 : 0.16), .clear]),
                                           center: center, startRadius: radius * 0.5, endRadius: haloRadius))
        context.drawLayer { moon in
            // The halo is diffuse; the disc keeps enough edge to read as a moon.
            moon.addFilter(.blur(radius: 1.8))
            let disc = CGRect(x: center.x - radius, y: center.y - radius,
                              width: radius * 2, height: radius * 2)
            let colors: [Color] = dark
                ? [Color(red: 0.94, green: 0.95, blue: 1).opacity(0.58), glow.opacity(0.30)]
                : [Color(red: 0.69, green: 0.72, blue: 0.86).opacity(0.57),
                   Color(red: 0.83, green: 0.87, blue: 1).opacity(0.62)]
            moon.fill(Path(ellipseIn: disc), with: .linearGradient(Gradient(colors: colors),
                      startPoint: CGPoint(x: disc.minX, y: disc.minY),
                      endPoint: CGPoint(x: disc.maxX, y: disc.maxY)))
            for patch in [CGPoint(x: -0.36, y: -0.12), CGPoint(x: 0.22, y: 0.28),
                          CGPoint(x: -0.15, y: 0.48)] {
                let point = CGPoint(x: center.x + patch.x * radius, y: center.y + patch.y * radius)
                let patchRadius = radius * 0.25
                moon.fill(Path(ellipseIn: CGRect(x: point.x - patchRadius, y: point.y - patchRadius,
                                                width: patchRadius * 2, height: patchRadius * 2)),
                          with: .radialGradient(Gradient(colors: [glow.opacity(0.20), .clear]),
                                                center: point, startRadius: 0, endRadius: patchRadius))
            }
        }
    }

    private func drawClouds(context: inout GraphicsContext, size: CGSize, dark: Bool) {
        // Two bounded, billowing silhouettes move at different speeds. The
        // nearer bank passes in front of the moon, providing a visible reference.
        for layer in 0..<2 {
            let near = layer == 1
            let drift = session.drift(channel: layer + 30, time: time,
                                      amplitude: CGSize(width: near ? 16 : 13, height: near ? 3.5 : 2.5))
            let center = CGPoint(x: size.width * (near ? 0.86 : 0.58) + drift.x,
                                 y: min(near ? 46 : 58, size.height * (near ? 0.78 : 0.58)) + drift.y)
            let width = min(near ? 190 : 170, max(100, size.width * (near ? 0.31 : 0.27)))
            let height: CGFloat = near ? 25 : 22
            let path = cloudPath(center: center, width: width, height: height)
            context.drawLayer { clouds in
                clouds.addFilter(.blur(radius: near ? 3 : 4))
                let colors: [Color] = dark
                    ? [Color(red: 0.50, green: 0.59, blue: 0.77).opacity(near ? 0.30 : 0.22),
                       Color(red: 0.13, green: 0.20, blue: 0.34).opacity(near ? 0.58 : 0.25)]
                    : [Color(red: 0.52, green: 0.58, blue: 0.78).opacity(near ? 0.27 : 0.17),
                       Color(red: 0.76, green: 0.82, blue: 0.95).opacity(0.25)]
                clouds.fill(path, with: .linearGradient(Gradient(colors: colors),
                            startPoint: CGPoint(x: center.x, y: center.y - height / 2),
                            endPoint: CGPoint(x: center.x, y: center.y + height / 2)))
            }
        }
    }

    private func cloudPath(center: CGPoint, width: CGFloat, height: CGFloat) -> Path {
        var path = Path()
        // Fill the overlapping ellipses as one path, so lobe intersections
        // do not darken or flicker when this shape passes over the moon.
        for lobe in [CGRect(x: -0.50, y: -0.05, width: 0.55, height: 0.65),
                     CGRect(x: -0.30, y: -0.34, width: 0.44, height: 0.90),
                     CGRect(x: -0.04, y: -0.50, width: 0.40, height: 1.05),
                     CGRect(x: 0.18, y: -0.13, width: 0.34, height: 0.65)] {
            path.addEllipse(in: CGRect(x: center.x + lobe.minX * width, y: center.y + lobe.minY * height,
                                       width: lobe.width * width, height: lobe.height * height))
        }
        return path
    }

    private static let stars: [CGPoint] = [
        CGPoint(x: 0.39, y: 0.28), CGPoint(x: 0.46, y: 0.68), CGPoint(x: 0.51, y: 0.17),
        CGPoint(x: 0.56, y: 0.43), CGPoint(x: 0.61, y: 0.77), CGPoint(x: 0.65, y: 0.22),
        CGPoint(x: 0.70, y: 0.55), CGPoint(x: 0.75, y: 0.16), CGPoint(x: 0.79, y: 0.72),
        CGPoint(x: 0.83, y: 0.36)
    ]
}

/// Retained hosting views outlive the panel's presentation. Window events,
/// rather than onDisappear, stop their background work when the panel closes.
struct ComposerWindowActivity: NSViewRepresentable {
    let onChange: (Bool) -> Void
    let onOpen: () -> Void

    func makeNSView(context: Context) -> ActivityView { ActivityView(onChange: onChange, onOpen: onOpen) }
    func updateNSView(_ view: ActivityView, context: Context) {
        view.onChange = onChange
        view.onOpen = onOpen
    }

    final class ActivityView: NSView {
        var onChange: (Bool) -> Void
        var onOpen: () -> Void
        private var wasVisible = false
        private var observers: [NSObjectProtocol] = []
        private var visibilityObservation: NSKeyValueObservation?
        private var lastValue: Bool?

        init(onChange: @escaping (Bool) -> Void, onOpen: @escaping () -> Void) {
            self.onChange = onChange
            self.onOpen = onOpen
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            visibilityObservation = nil
            if let window {
                visibilityObservation = window.observe(\.isVisible, options: [.new]) { [weak self] _, _ in
                    self?.publishActivity()
                }
                for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                             NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification] {
                    observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        self?.publishActivity()
                    })
                }
            }
            publishActivity()
        }

        private func publishActivity() {
            // Capture visibility at the event, before deferring SwiftUI state
            // updates. A quick close/reopen must retain its hidden transition.
            let visible = window?.isVisible == true
            let opened = visible && !wasVisible
            wasVisible = visible
            let active = visible && window?.isKeyWindow == true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if opened { self.onOpen() }
                guard self.lastValue != active else { return }
                self.lastValue = active
                self.onChange(active)
            }
        }
    }
}
