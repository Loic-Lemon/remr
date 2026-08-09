import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var instance: AppDelegate?

    let store = ReminderStore()

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var serviceWindow: NSWindow?
    private var serviceHosting: NSHostingController<AnyView>?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppDelegate.instance = self

        NSApp.servicesProvider = ServiceHandler.shared
        store.start()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = StatusIcon.makeIcon()
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "remr"
        }
        statusItem = item

        let popover = NSPopover()
        // `.transient` closes the popover when it resigns key status — which
        // happens the instant a context menu (its own window) opens, killing
        // the menu. `.applicationDefined` keeps the popover up; outside-click
        // dismissal is handled by the global monitor below.
        popover.behavior = .applicationDefined
        // No default open animation; closing is our own short fade (below).
        popover.animates = false
        popover.contentViewController = NSHostingController(
            rootView: ContentView().environmentObject(store)
        )
        popover.contentSize = NSSize(width: 400, height: 600)
        self.popover = popover

        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, let popover = self.popover, popover.isShown else { return }
                self.closePopover()
            }
        }
    }

    // MARK: - Status item

    @objc private func statusItemClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            // A status-item menu is its own window; close the popover first
            // so the two don't stack.
            if popover.isShown { closePopover() }
            let menu = NSMenu()
            menu.addItem(withTitle: "Refresh", action: #selector(refreshData), keyEquivalent: "")
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem.popUpMenu(menu)
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            closePopover()
        } else {
            store.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Liquid glass: the popover window is transparent so the SwiftUI
            // material below blurs the desktop behind it.
            if let window = popover.contentViewController?.view.window {
                window.isOpaque = false
                window.backgroundColor = .clear
            }
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// Fade the popover window out, then close it. Used everywhere the
    /// popover dismisses — the default close animation is disabled
    /// (`animates = false`). Fading the window (not just the content view)
    /// keeps the shadow and arrow in sync so there is no leftover frame.
    private func closePopover() {
        guard popover.isShown, let window = popover.contentViewController?.view.window else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.allowsImplicitAnimation = true
            window.animator().alphaValue = 0
        } completionHandler: {
            self.popover.performClose(nil)
            window.alphaValue = 1
        }
    }

    @objc private func refreshData() {
        store.refresh()
    }

    // `.transient` used to close on deactivation; keep that behavior explicit.
    func applicationDidResignActive(_ notification: Notification) {
        if popover.isShown { closePopover() }
    }

    // MARK: - Service window

    /// Brings up (or reuses) the "New Reminders" window with `text` prefilled.
    func showBulkPreview(text: String) {
        let rootView = AnyView(NewReminderView(prefillText: text).environmentObject(store))
        if let hosting = serviceHosting {
            hosting.rootView = rootView
            serviceWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hosting)
        window.title = "New Reminders"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 460, height: 600))
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        serviceWindow = window
        serviceHosting = hosting
    }
}
