import AppKit
import QuartzCore
import SwiftUI

/// An arrowless menu window with short, interruptible opening motion. Kept separate from
/// the native popovers used by larger guide, recovery, and detail surfaces.
struct FastDropdownPresenter: NSViewRepresentable {
    let isPresented: Bool
    let content: AnyView
    let onDismiss: () -> Void
    var preferAbove = false

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> FastPopoverPresenter.AnchorView {
        let view = FastPopoverPresenter.AnchorView()
        context.coordinator.anchor = view
        view.onLayout = { [weak coordinator = context.coordinator] in coordinator?.showIfReady() }
        return view
    }

    func updateNSView(_ view: FastPopoverPresenter.AnchorView, context: Context) {
        context.coordinator.anchor = view
        context.coordinator.preferAbove = preferAbove
        context.coordinator.onDismiss = onDismiss
        context.coordinator.update(isPresented: isPresented, content: content)
    }

    static func dismantleNSView(_ view: FastPopoverPresenter.AnchorView, coordinator: Coordinator) {
        view.onLayout = nil
        coordinator.close()
    }

    static func hasOpenMenu(in window: NSWindow?) -> Bool {
        window?.childWindows?.contains { $0 is MenuPanel && $0.isVisible } == true
    }

    final class MenuPanel: NSPanel {
        // Keep the owning window's glass and controls in their active appearance.
        // Keyboard events are delivered to our responder without moving key focus.
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }

        var onKey: ((NSEvent) -> Bool)?
        var onDismiss: (() -> Void)?

        func performEditingCommand(_ event: NSEvent) -> Bool {
            guard let editor = firstResponder as? NSTextView,
                  event.modifierFlags.intersection([.command, .control, .option]) == .command else { return false }
            // Menu commands normally target the key window's editor. Target our
            // search editor explicitly while preserving the owner's focus.
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "a": editor.selectAll(nil)
            case "c": editor.copy(nil)
            case "x": editor.cut(nil)
            case "v": editor.paste(nil)
            case "z":
                if event.modifierFlags.contains(.shift) { editor.undoManager?.redo() }
                else { editor.undoManager?.undo() }
            default: return false
            }
            return true
        }

        override func sendEvent(_ event: NSEvent) {
            // NSWindow normally delivers typing only to its key window. This
            // menu deliberately keeps that status on its owner instead.
            switch event.type {
            case .keyDown:
                if onKey?(event) == true { return }
                if event.keyCode == 53 { onDismiss?(); return }
                firstResponder?.keyDown(with: event)
            case .keyUp: firstResponder?.keyUp(with: event)
            case .flagsChanged: firstResponder?.flagsChanged(with: event)
            default: super.sendEvent(event)
            }
        }
    }

    final class Coordinator {
        weak var anchor: NSView?
        var onDismiss: () -> Void = {}
        var preferAbove = false
        private var panel: MenuPanel?
        private var hosting: NSHostingController<AnyView>?
        private var wantsPresented = false
        private var isClosing = false
        private var generation = 0
        private var localMonitor: Any?
        private var globalMonitor: Any?
        private var keyboardMonitor: Any?
        private var targetFrame: NSRect?
        private var observers: [NSObjectProtocol] = []

        func update(isPresented: Bool, content: AnyView) {
            wantsPresented = isPresented
            if isPresented {
                let settings = MainActor.assumeIsolated { SettingsStore.shared }
                let root = AnyView(content.remrDropdownSurface()
                    .remrAppearance(using: settings)
                    .onExitCommand { [weak self] in self?.dismiss() })
                if let hosting {
                    hosting.rootView = root
                } else {
                    let hosting = NSHostingController(rootView: root)
                    hosting.sizingOptions = [.preferredContentSize]
                    self.hosting = hosting
                    let panel = MenuPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
                    panel.onDismiss = { [weak self] in self?.dismiss() }
                    panel.isReleasedWhenClosed = false
                    panel.isOpaque = false
                    panel.backgroundColor = .clear
                    panel.hasShadow = true
                    panel.hidesOnDeactivate = false
                    panel.isMovable = false
                    panel.animationBehavior = .none
                    panel.contentViewController = hosting
                    self.panel = panel
                }
                MainActor.assumeIsolated { panel?.appearance = settings.appearance.nsAppearance }
                if isClosing {
                    generation &+= 1
                    isClosing = false
                    animateOpacity(to: 1, duration: 0.10)
                }
                showIfReady()
            } else if panel?.isVisible == true, !isClosing {
                isClosing = true
                generation &+= 1
                let current = generation
                animateOpacity(to: 0, duration: 0.07) { [weak self] in
                    guard let self, self.generation == current else { return }
                    self.close()
                }
            }
        }

        func showIfReady() {
            guard wantsPresented, let anchor, let parent = anchor.window,
                  !anchor.bounds.isEmpty, let panel, let hosting else { return }
            hosting.view.layoutSubtreeIfNeeded()
            let size = hosting.view.fittingSize
            guard size.width > 0, size.height > 0 else { return }
            let rect = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            let screen = parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? parent.frame
            let frame = DropdownGeometry.frame(anchor: rect, size: size, screen: screen, preferAbove: preferAbove)
            if targetFrame != frame {
                targetFrame = frame
                panel.setFrame(frame, display: true)
            }
            guard !panel.isVisible else { return }
            panel.level = parent.level
            parent.addChildWindow(panel, ordered: .above)
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            panel.alphaValue = reduceMotion ? 1 : 0
            // Start four points closer to the trigger; no scaling or spring overshoot.
            if !reduceMotion {
                let offset: CGFloat = frame.midY < rect.midY ? 4 : -4
                panel.setFrame(frame.offsetBy(dx: 0, dy: offset), display: false)
            }
            installMonitors()
            panel.orderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = reduceMotion ? 0 : 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrame(frame, display: true)
            }
            MainActor.assumeIsolated { AppHaptics.screenOpened() }
        }

        private func animateOpacity(to opacity: CGFloat, duration: TimeInterval, completion: (() -> Void)? = nil) {
            guard let panel else { completion?(); return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : duration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = opacity
            } completionHandler: { completion?() }
        }

        private func installMonitors() {
            guard localMonitor == nil else { return }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self, self.wantsPresented else { return event }
                if event.window === self.panel || event.window?.isSheet == true { return event }
                if let clicked = event.window, clicked.parent === self.panel { return event }
                if let anchor = self.anchor, event.window === anchor.window,
                   anchor.bounds.contains(anchor.convert(event.locationInWindow, from: nil)) { return event }
                self.dismiss()
                return event
            }
            keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
                guard let self, self.wantsPresented, let panel = self.panel, panel.isVisible,
                      event.window === self.anchor?.window else { return event }
                if event.type == .keyDown, event.modifierFlags.contains(.command) {
                    return panel.performEditingCommand(event) ? nil : event
                }
                // Give the menu's responder an event in its own window coordinates
                // without making that window key or changing the owner's responder.
                let isFlags = event.type == .flagsChanged
                guard let routed = NSEvent.keyEvent(with: event.type, location: event.locationInWindow,
                                                   modifierFlags: event.modifierFlags, timestamp: event.timestamp,
                                                   windowNumber: panel.windowNumber, context: nil,
                                                   characters: isFlags ? "" : (event.characters ?? ""),
                                                   charactersIgnoringModifiers: isFlags ? "" : (event.charactersIgnoringModifiers ?? ""),
                                                   isARepeat: isFlags ? false : event.isARepeat, keyCode: event.keyCode) else { return event }
                panel.sendEvent(routed)
                return nil
            }
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.dismiss()
            }
            for name in [NSApplication.didResignActiveNotification, Notification.Name.remrPopoverClosing] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.dismiss()
                })
            }
        }

        private func dismiss() {
            guard wantsPresented else { return }
            wantsPresented = false
            onDismiss()
        }

        func close() {
            wantsPresented = false
            generation &+= 1
            isClosing = false
            if let localMonitor { NSEvent.removeMonitor(localMonitor) }
            if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
            if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
            localMonitor = nil
            globalMonitor = nil
            keyboardMonitor = nil
            targetFrame = nil
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            if let panel {
                let parent = panel.parent
                parent?.removeChildWindow(panel)
                panel.orderOut(nil)
            }
            hosting = nil
            panel = nil
        }

        deinit { close() }
    }
}

extension View {
    func remrDropdown<Content: View>(isPresented: Binding<Bool>, arrowEdge: Edge = .top,
                                    @ViewBuilder content: () -> Content) -> some View {
        background {
            FastDropdownPresenter(isPresented: isPresented.wrappedValue,
                                  content: AnyView(content()),
                                  onDismiss: { isPresented.wrappedValue = false },
                                  preferAbove: arrowEdge == .bottom)
        }
    }
}
