import AppKit
import SwiftUI

/// Native popover presentation shared by the guide and recovery surfaces.
/// Opening is immediate; controlled closes fade the window out briefly before
/// dismissing it so the arrow and shadow leave with the content.
struct FastPopoverPresenter: NSViewRepresentable {
    let isPresented: Bool
    let content: AnyView
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.anchor = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.anchor = nsView
        context.coordinator.onDismiss = onDismiss
        context.coordinator.update(isPresented: isPresented, content: content)
    }

    final class Coordinator: NSObject, NSPopoverDelegate {
        weak var anchor: NSView?
        var onDismiss: () -> Void
        private var popover: NSPopover?
        private var localMonitor: Any?
        private var globalMonitor: Any?
        private var closeGeneration = 0
        private var isClosing = false

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func update(isPresented: Bool, content: AnyView) {
            if isPresented {
                closeGeneration &+= 1
                isClosing = false

                let popover = self.popover ?? makePopover(content: content)
                self.popover = popover
                if let hosting = popover.contentViewController as? NSHostingController<AnyView> {
                    hosting.rootView = content
                }
                installMonitors()
                popover.contentViewController?.view.window?.alphaValue = 1
                applyAppearance(to: popover)

                guard !popover.isShown, let anchor, !anchor.bounds.isEmpty else { return }
                DispatchQueue.main.async { [weak self, weak popover, weak anchor] in
                    guard let self, let popover, let anchor,
                          !popover.isShown, !anchor.bounds.isEmpty else { return }
                    popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
                    popover.contentViewController?.view.window?.alphaValue = 1
                    self.applyAppearance(to: popover)
                }
            } else if let popover, popover.isShown, !isClosing {
                fadeClose(popover)
            }
        }

        private func makePopover(content: AnyView) -> NSPopover {
            let popover = NSPopover()
            popover.behavior = .applicationDefined
            popover.animates = false
            popover.delegate = self
            popover.contentViewController = NSHostingController(rootView: content)
            return popover
        }

        private func applyAppearance(to popover: NSPopover) {
            Task { @MainActor [weak popover] in
                popover?.contentViewController?.view.window?.appearance = SettingsStore.shared.appearance.nsAppearance
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
                if let anchor = self.anchor, event.window === anchor.window {
                    let point = anchor.convert(event.locationInWindow, from: nil)
                    if anchor.bounds.contains(point) {
                        return event
                    }
                }
                Task { @MainActor [weak self] in
                    self?.onDismiss()
                }
                return event
            }

            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.onDismiss()
                }
            }
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
            onDismiss()
        }

        deinit {
            if let localMonitor { NSEvent.removeMonitor(localMonitor) }
            if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
            popover?.close()
        }
    }
}
