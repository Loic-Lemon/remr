import AppKit
import SwiftUI

/// Native popover presentation shared by the toolbar pickers, the guide and
/// recovery surfaces. A real `NSPopover` gives the card its own window above
/// everything else, the native Liquid Glass surface on macOS 26, its own
/// outside-click dismissal and a shadow that tracks the content, instead of a
/// hand-positioned borderless panel that has to reimplement all four.
struct FastPopoverPresenter: NSViewRepresentable {
    let isPresented: Bool
    let content: AnyView
    let onDismiss: () -> Void
    /// Show the card above the anchor instead of below it.
    var preferAbove = false

    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.onLayout = { [weak coordinator = context.coordinator] in coordinator?.showIfReady() }
        context.coordinator.anchor = view
        return view
    }

    func updateNSView(_ view: AnchorView, context: Context) {
        let coordinator = context.coordinator
        coordinator.anchor = view
        coordinator.onDismiss = onDismiss
        coordinator.preferAbove = preferAbove
        coordinator.update(isPresented: isPresented, content: content)
    }

    static func dismantleNSView(_ view: AnchorView, coordinator: Coordinator) {
        view.onLayout = nil
        coordinator.close()
    }

    /// The trigger's own view. The popover anchors to it, so re-anchor whenever
    /// SwiftUI lays it out again — the notch surface resizes as it opens.
    final class AnchorView: NSView {
        var onLayout: (() -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleLayout()
        }
        override func layout() {
            super.layout()
            scheduleLayout()
        }
        private func scheduleLayout() {
            DispatchQueue.main.async { [weak self] in self?.onLayout?() }
        }
    }

    final class Coordinator: NSObject, NSPopoverDelegate {
        weak var anchor: NSView?
        var onDismiss: () -> Void
        var preferAbove = false
        private var popover: NSPopover?
        private var localMonitor: Any?
        private var globalMonitor: Any?
        private var observers: [NSObjectProtocol] = []
        private var wantsPresented = false
        private var closeGeneration = 0
        private var isClosing = false

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func update(isPresented: Bool, content: AnyView) {
            wantsPresented = isPresented
            if isPresented {
                closeGeneration &+= 1
                isClosing = false
                let popover = self.popover ?? makePopover(content: content)
                self.popover = popover
                if let hosting = popover.contentViewController as? NSHostingController<AnyView> {
                    hosting.rootView = appearanceAwareContent(content)
                }
                installMonitors()
                applyAppearance(to: popover)
                showIfReady()
            } else if let popover, popover.isShown, !isClosing {
                fadeClose(popover)
            }
        }

        /// The anchor can be laid out (and its window revealed) after the
        /// presentation flag flips, so the update path and the layout hook both
        /// funnel here rather than calling `show` from one place.
        func showIfReady() {
            guard wantsPresented, let popover, !popover.isShown else { return }
            guard let anchor, anchor.window != nil, !anchor.bounds.isEmpty else { return }
            DispatchQueue.main.async { [weak self, weak popover, weak anchor] in
                guard let self, let popover, let anchor,
                      self.wantsPresented, !popover.isShown,
                      anchor.window != nil, !anchor.bounds.isEmpty else { return }
                popover.show(relativeTo: anchor.bounds, of: anchor,
                             preferredEdge: self.preferAbove ? .maxY : .minY)
                if popover.isShown { AppHaptics.screenOpened() }
                self.applyAppearance(to: popover)
            }
        }

        private func makePopover(content: AnyView) -> NSPopover {
            let popover = NSPopover()
            popover.behavior = .applicationDefined
            popover.animates = true
            popover.delegate = self
            let hosting = NSHostingController(rootView: appearanceAwareContent(content))
            // The pickers change height with their content (list counts, tag
            // matches); without this the popover keeps the first size.
            hosting.sizingOptions = [.preferredContentSize]
            popover.contentViewController = hosting
            return popover
        }

        private func appearanceAwareContent(_ content: AnyView) -> AnyView {
            let settings = MainActor.assumeIsolated { SettingsStore.shared }
            return AnyView(content.remrAppearance(using: settings)
                .onExitCommand(perform: onDismiss))
        }

        private func applyAppearance(to popover: NSPopover) {
            Task { @MainActor [weak popover] in
                popover?.contentViewController?.view.window?.appearance =
                    SettingsStore.shared.appearance.nsAppearance
            }
        }

        private func installMonitors() {
            guard localMonitor == nil else { return }

            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self, let popover = self.popover, popover.isShown else { return event }
                if let popoverWindow = popover.contentViewController?.view.window,
                   event.window === popoverWindow {
                    return event
                }
                // Clicks in our own presented sheets (e.g. the "Delete
                // Forever?" confirmation dialog) are part of the
                // popover's flow — a click there must not dismiss it.
                if let clicked = event.window {
                    if clicked.isSheet { return event }
                    if let popoverWindow = popover.contentViewController?.view.window,
                       clicked.parent === popoverWindow {
                        return event
                    }
                }
                if let anchor = self.anchor, event.window === anchor.window {
                    let point = anchor.convert(event.locationInWindow, from: nil)
                    if anchor.bounds.contains(point) {
                        return event
                    }
                }
                DispatchQueue.main.async { [weak self] in self?.dismiss() }
                return event
            }

            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                DispatchQueue.main.async { [weak self] in self?.dismiss() }
            }

            // The card must not outlive the surface that owns it.
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

        private func fadeClose(_ popover: NSPopover) {
            isClosing = true
            closeGeneration &+= 1
            let generation = closeGeneration

            guard let window = popover.contentViewController?.view.window else {
                isClosing = false
                popover.performClose(nil)
                return
            }

            window.alphaValue = 1
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.08
                context.allowsImplicitAnimation = true
                window.animator().alphaValue = 0
            } completionHandler: { [weak self, weak popover, weak window] in
                guard let self, generation == self.closeGeneration else { return }
                MainActor.assumeIsolated {
                    popover?.performClose(nil)
                    window?.alphaValue = 1
                    self.isClosing = false
                }
            }
        }

        func popoverDidClose(_ notification: Notification) {
            isClosing = false
            // An externally closed popover (Escape, the anchor's own state
            // machine) must not leave the presentation flag stuck on.
            if wantsPresented {
                wantsPresented = false
                onDismiss()
            }
        }

        func close() {
            wantsPresented = false
            isClosing = false
            if let localMonitor { NSEvent.removeMonitor(localMonitor) }
            if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
            localMonitor = nil
            globalMonitor = nil
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers.removeAll()
            popover?.performClose(nil)
            popover = nil
        }

        deinit {
            if let localMonitor { NSEvent.removeMonitor(localMonitor) }
            if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            popover?.close()
        }
    }
}

extension View {
    /// Uses the same card chrome for all app-owned popover content.
    func remrPopover<Content: View>(isPresented: Binding<Bool>, arrowEdge: Edge = .bottom,
                                   @ViewBuilder content: () -> Content) -> some View {
        background {
            FastPopoverPresenter(isPresented: isPresented.wrappedValue,
                                 content: AnyView(content()),
                                 onDismiss: { isPresented.wrappedValue = false },
                                 preferAbove: arrowEdge == .bottom)
        }
    }
}
