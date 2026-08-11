import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var instance: AppDelegate?

    let store = ReminderStore()

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var serviceWindow: NSWindow?
    private var serviceHosting: NSHostingController<AnyView>?
    private var hotKeyRef: EventHotKeyRef?
    private let hotKeySignature: OSType = 0x72656D72 // "remr"
    private var currentHotkeyCombo: KeyCombo?
    private var settingsCancellables: Set<AnyCancellable> = []

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
            rootView: ContentView().environmentObject(store).environmentObject(SettingsStore.shared)
        )
        popover.contentSize = NSSize(width: 400, height: 600)
        self.popover = popover

        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, let popover = self.popover, popover.isShown else { return }
                self.closePopover()
            }
        }

        registerHotKey()

        SettingsStore.shared.$bindings
            .dropFirst()   // skip the initial value emission on subscribe
            .sink { [weak self] _ in self?.reapplyHotKey() }
            .store(in: &settingsCancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
    }

    private func registerHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { AppDelegate.instance?.togglePopover() }
            return noErr
        }, 1, &eventType, nil, nil)
        reapplyHotKey()
    }

    /// Register the current toggle combo; on failure (another app owns it), revert
    /// the stored binding to the previously-working combo and surface an error.
    private func reapplyHotKey() {
        let combo = SettingsStore.shared.combo(for: .togglePopover)
        guard combo != currentHotkeyCombo else { return }
        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: 1)
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef); self.hotKeyRef = nil }
        // The user disabled the global hotkey: just unregister, nothing to bind.
        if combo.isEmpty {
            currentHotkeyCombo = combo
            SettingsStore.shared.errorMessage = nil
            return
        }
        guard let keyCode = combo.globalHotkeyKeyCode else {
            // SettingsStore rejects modifier-less and non-single-key combos on
            // assign; this is a defensive fallback for any other path in.
            SettingsStore.shared.errorMessage = "The global shortcut needs exactly one key (e.g. ⌥⌘R)"
            if let previous = currentHotkeyCombo {
                SettingsStore.shared.assign(previous, to: .togglePopover)  // reverts + persists
            }
            return
        }
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), combo.carbonModifierFlags, hotKeyID,
                                         GetApplicationEventTarget(), 0, &newRef)
        if status == noErr {
            hotKeyRef = newRef
            currentHotkeyCombo = combo
            SettingsStore.shared.errorMessage = nil
        } else {
            // Re-register the old combo (just freed above) and revert the setting.
            if let previous = currentHotkeyCombo, !previous.isEmpty,
               let previousKeyCode = previous.globalHotkeyKeyCode {
                RegisterEventHotKey(UInt32(previousKeyCode), previous.carbonModifierFlags, hotKeyID,
                                    GetApplicationEventTarget(), 0, &hotKeyRef)
                SettingsStore.shared.assign(previous, to: .togglePopover)  // reverts + persists
            }
            SettingsStore.shared.errorMessage = "“\(combo.displayString)” is already in use by another app"
        }
    }

    // MARK: - Status item

    @objc private func statusItemClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            // A status-item menu is its own window; close the popover first
            // so the two don't stack.
            if popover.isShown { closePopover() }
            let menu = NSMenu()
            let refreshItem = menu.addItem(withTitle: "Refresh", action: #selector(refreshData), keyEquivalent: "")
            // Nil-target menu items resolve through the responder chain, which
            // ends at NSApp and never includes the AppDelegate — Refresh would
            // silently do nothing. Quit below keeps its nil target on purpose
            // (NSApplication.terminate lives on NSApp, the chain's last link).
            refreshItem.target = self
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            // statusItem.popUpMenu(_:) is deprecated; pop the menu from the
            // button directly. Deliberately NOT statusItem.menu — that would
            // swallow left-clicks and break the popover toggle.
            if let button = statusItem.button {
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
            }
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
            // Hardening: an .accessory app shown from the status item is not
            // activated by the status-item click alone, and local NSEvent
            // monitors only see hardware key events delivered to an active app.
            // Activating here guarantees the popover (and its inline Settings
            // view) receives keyboard input. Click-into-popover already
            // activates; this makes the popover keyboard-usable immediately.
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Fade the popover window out, then close it. Used everywhere the
    /// popover dismisses — the default close animation is disabled
    /// (`animates = false`). Fading the window (not just the content view)
    /// keeps the shadow and arrow in sync so there is no leftover frame.
    func closePopover() {
        guard popover.isShown, let window = popover.contentViewController?.view.window else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.allowsImplicitAnimation = true
            window.animator().alphaValue = 0
        } completionHandler: {
            // The completion already runs on main; assumeIsolated silences the
            // Sendable-closure warning on the SDKs that annotate it.
            MainActor.assumeIsolated {
                self.popover.performClose(nil)
                window.alphaValue = 1
            }
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
