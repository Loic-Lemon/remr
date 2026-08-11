import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

@MainActor
private final class QuickAddPanel: NSPanel {
    // Borderless windows do not become key by default. The text editor in the
    // quick-add surface needs the panel to accept keyboard input (including
    // Escape), while it must never become the application's main window.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var instance: AppDelegate?

    let store = ReminderStore()

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var serviceWindow: NSWindow?
    private var serviceHosting: NSHostingController<AnyView>?
    private var quickAddWindow: NSPanel?
    private var quickAddHosting: NSHostingController<AnyView>?
    private var mouseDownGlobalMonitor: Any?
    private var mouseDownLocalMonitor: Any?
    private var quickAddCloseGeneration = 0
    private var toggleHotKeyRef: EventHotKeyRef?
    private var quickAddHotKeyRef: EventHotKeyRef?
    private let hotKeySignature: OSType = 0x72656D72 // "remr"
    private var currentToggleHotkeyCombo: KeyCombo?
    private var currentQuickAddHotkeyCombo: KeyCombo?
    private var hotKeyErrors: [BindableAction: String] = [:]
    private var settingsCancellables: Set<AnyCancellable> = []
    func applicationWillTerminate(_ notification: Notification) {
        if let toggleHotKeyRef { UnregisterEventHotKey(toggleHotKeyRef) }
        if let quickAddHotKeyRef { UnregisterEventHotKey(quickAddHotKeyRef) }
        if let mouseDownGlobalMonitor {
            NSEvent.removeMonitor(mouseDownGlobalMonitor)
            self.mouseDownGlobalMonitor = nil
        }
        if let mouseDownLocalMonitor {
            NSEvent.removeMonitor(mouseDownLocalMonitor)
            self.mouseDownLocalMonitor = nil
        }
    }


    private func registerHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            guard let event else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotKeyID)
            guard status == noErr else { return status }
            DispatchQueue.main.async {
                guard let app = AppDelegate.instance else { return }
                switch hotKeyID.id {
                case 1: app.togglePopover()
                case 2: app.showQuickAdd()
                default: break
                }
            }
            return noErr
        }, 1, &eventType, nil, nil)
        reapplyHotKeys()
    }

    private func reapplyHotKeys() {
        reapplyHotKey(.togglePopover)
        reapplyHotKey(.quickAdd)
    }

    /// Re-register one global binding without disturbing the other action's
    /// registration. A failed replacement restores this action's last working
    /// registration and reports the conflict through SettingsStore.
    private func reapplyHotKey(_ action: BindableAction) {
        let settings = SettingsStore.shared
        let combo = settings.combo(for: action)
        let current: KeyCombo?
        let ref: EventHotKeyRef?
        switch action {
        case .togglePopover:
            current = currentToggleHotkeyCombo
            ref = toggleHotKeyRef
        case .quickAdd:
            current = currentQuickAddHotkeyCombo
            ref = quickAddHotKeyRef
        default:
            return
        }
        if combo == current && (combo.isEmpty || ref != nil) { return }

        switch action {
        case .togglePopover:
            if let ref { UnregisterEventHotKey(ref) }
            toggleHotKeyRef = nil
            currentToggleHotkeyCombo = nil
        case .quickAdd:
            if let ref { UnregisterEventHotKey(ref) }
            quickAddHotKeyRef = nil
            currentQuickAddHotkeyCombo = nil
        default:
            return
        }

        if combo.isEmpty {
            setCurrentHotkey(combo, ref: nil, for: action)
            hotKeyErrors[action] = nil
            publishHotKeyError()
            return
        }
        guard let keyCode = combo.globalHotkeyKeyCode else {
            let message = "The global shortcut needs exactly one key (e.g. ⌥⌘R)"
            restoreHotKey(current: current, action: action, settings: settings, message: message)
            return
        }

        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), combo.carbonModifierFlags,
                                         EventHotKeyID(signature: hotKeySignature,
                                                      id: hotKeyID(for: action)),
                                         GetApplicationEventTarget(), 0, &newRef)
        if status == noErr {
            setCurrentHotkey(combo, ref: newRef, for: action)
            hotKeyErrors[action] = nil
            publishHotKeyError()
        } else {
            restoreHotKey(current: current, action: action, settings: settings,
                          message: "“\(combo.displayString)” is already in use by another app")
        }
    }

    private func hotKeyID(for action: BindableAction) -> UInt32 {
        switch action {
        case .togglePopover: return 1
        case .quickAdd: return 2
        default: return 0
        }
    }

    private func setCurrentHotkey(_ combo: KeyCombo, ref: EventHotKeyRef?, for action: BindableAction) {
        switch action {
        case .togglePopover:
            currentToggleHotkeyCombo = combo
            toggleHotKeyRef = ref
        case .quickAdd:
            currentQuickAddHotkeyCombo = combo
            quickAddHotKeyRef = ref
        default: break
        }
    }

    private func restoreHotKey(current: KeyCombo?, action: BindableAction,
                               settings: SettingsStore, message: String) {
        if let current, !current.isEmpty, let keyCode = current.globalHotkeyKeyCode {
            var restoredRef: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(keyCode), current.carbonModifierFlags,
                                             EventHotKeyID(signature: hotKeySignature,
                                                          id: hotKeyID(for: action)),
                                             GetApplicationEventTarget(), 0, &restoredRef)
            if status == noErr {
                setCurrentHotkey(current, ref: restoredRef, for: action)
            }
        } else if let current {
            setCurrentHotkey(current, ref: nil, for: action)
        }
        if let current {
            settings.assign(current, to: action)
        }
        hotKeyErrors[action] = message
        publishHotKeyError()
    }
    private func publishHotKeyError() {
        let settings = SettingsStore.shared
        settings.errorMessage = BindableAction.allCases
            .compactMap { hotKeyErrors[$0] }
            .first
    }

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
        // Use the native quick opening animation; closing remains the custom
        // short window fade below so outside-click dismissal stays unchanged.
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: ContentView().environmentObject(store).environmentObject(SettingsStore.shared)
        )
        popover.contentSize = NSSize(width: 400, height: 600)
        self.popover = popover

        mouseDownGlobalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.popover?.isShown == true { self.closePopover() }
                if self.quickAddWindow?.isVisible == true { self.closeQuickAdd() }
            }
        }

        mouseDownLocalMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            // Capture only the window number before hopping to the main actor;
            // NSEvent itself is not Sendable. Local monitors cover clicks in
            // other windows owned by this process, while the global monitor
            // above covers windows owned by other applications.
            let clickedWindowNumber = event.window?.windowNumber
            Task { @MainActor in
                guard let self, let quickAddWindow = self.quickAddWindow,
                      quickAddWindow.isVisible,
                      clickedWindowNumber != quickAddWindow.windowNumber else { return }
                self.closeQuickAdd()
            }
            return event
        }

        registerHotKey()

        SettingsStore.shared.$bindings
            .dropFirst()   // skip the initial value emission on subscribe
            .sink { [weak self] _ in self?.reapplyHotKeys() }
            .store(in: &settingsCancellables)

        SettingsStore.shared.$appearance
            .sink { [weak self] appearance in self?.applyAppearance(appearance) }
            .store(in: &settingsCancellables)
    }

    private func applyAppearance(_ appearance: AppearanceMode) {
        // Apply the appearance to existing windows rather than changing the
        // application host. This updates native glass in place and avoids
        // invalidating the inline Settings view while its picker is active.
        let nsAppearance = appearance.nsAppearance
        for window in NSApp.windows {
            window.appearance = nsAppearance
        }
        serviceWindow?.appearance = nsAppearance
        quickAddWindow?.appearance = nsAppearance
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
            // macOS 26's NSPopover supplies the native Liquid Glass surface.
            // Older systems need the transparent host for the material fallback.
            if #unavailable(macOS 26.0) {
                if let window = popover.contentViewController?.view.window {
                    window.isOpaque = false
                    window.backgroundColor = .clear
                }
            }
            applyAppearance(SettingsStore.shared.appearance)
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
    /// popover dismisses. The native animation is enabled for opening, but is
    /// disabled around `performClose` so this custom fade remains the only
    /// close transition.
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
                self.popover.animates = false
                self.popover.performClose(nil)
                self.popover.animates = true
                window.alphaValue = 1
            }
        }
    }

    /// Opens a fresh quick-add session in a reusable centered floating panel.
    func showQuickAdd() {
        if popover.isShown { closePopover() }

        // Height reports can arrive after SwiftUI has replaced the hosting
        // root view, so identify each presentation to reject stale reports.
        quickAddCloseGeneration &+= 1
        let sessionGeneration = quickAddCloseGeneration
        let sessionID = UUID()
        let rootView = AnyView(
            QuickAddView(sessionID: sessionID,
                         onCancel: { [weak self] in self?.closeQuickAdd() },
                         onCreated: { [weak self] in self?.closeQuickAdd() },
                         onHeightChange: { [weak self] height in
                             guard let self,
                                   self.quickAddCloseGeneration == sessionGeneration else { return }
                             self.resizeQuickAdd(to: height)
                         })
                .environmentObject(store)
                .environmentObject(SettingsStore.shared)
        )

        let window: NSPanel
        if let existingWindow = quickAddWindow, let hosting = quickAddHosting {
            hosting.rootView = rootView
            window = existingWindow
        } else {
            let hosting = NSHostingController(rootView: rootView)
            let newWindow = QuickAddPanel(contentViewController: hosting)
            newWindow.styleMask = [.borderless]
            newWindow.setContentSize(NSSize(width: 500, height: 120))
            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            newWindow.hasShadow = true
            newWindow.isReleasedWhenClosed = false
            newWindow.isFloatingPanel = true
            newWindow.level = .floating
            newWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            newWindow.hidesOnDeactivate = false
            newWindow.becomesKeyOnlyIfNeeded = false
            quickAddHosting = hosting
            quickAddWindow = newWindow
            window = newWindow
        }

        // Restore the reusable panel before ordering it front. This keeps a
        // rapid reopen fully visible and invalidates any pending fade.
        window.alphaValue = 1

        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        if let screen {
            let visibleFrame = screen.visibleFrame
            let frame = window.frame
            window.setFrameOrigin(NSPoint(x: visibleFrame.midX - frame.width / 2,
                                          y: visibleFrame.midY - frame.height / 2))
        } else {
            window.center()
        }
        applyAppearance(SettingsStore.shared.appearance)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Adjusts only the panel's height to match the hosting view's ideal size.
    /// The top edge stays fixed so growth extends downward — typing never
    /// yanks the popup upward.
    private func resizeQuickAdd(to idealHeight: CGFloat) {
        guard let window = quickAddWindow,
              window.isVisible,
              idealHeight.isFinite,
              idealHeight > 0 else { return }

        let screen = window.screen
            ?? NSScreen.screens.first { screen in
                screen.visibleFrame.contains(NSPoint(x: window.frame.midX, y: window.frame.midY))
            }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        let visibleFrame = screen.visibleFrame
        let minimumHeight: CGFloat = 112
        let maximumHeight = max(minimumHeight, visibleFrame.height - 24)
        let targetHeight = min(max(idealHeight, minimumHeight), maximumHeight)
        let currentFrame = window.frame
        guard abs(currentFrame.height - targetHeight) >= 0.5 else { return }

        // Top edge anchored: the panel grows downward from its current top,
        // so typing never shifts the popup upward.
        let targetFrame = NSRect(x: currentFrame.minX,
                                 y: currentFrame.maxY - targetHeight,
                                 width: currentFrame.width,
                                 height: targetHeight)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            window.animator().setFrame(targetFrame, display: true)
        }
    }

    private func closeQuickAdd() {
        guard let window = quickAddWindow else { return }
        guard window.isVisible else {
            window.alphaValue = 1
            return
        }

        quickAddCloseGeneration &+= 1
        let generation = quickAddCloseGeneration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.allowsImplicitAnimation = true
            window.animator().alphaValue = 0
        } completionHandler: { [weak self, weak window] in
            MainActor.assumeIsolated {
                guard let self, let window,
                      self.quickAddCloseGeneration == generation else { return }
                window.close()
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
        if quickAddWindow?.isVisible == true { closeQuickAdd() }
    }

    // MARK: - Service window

    /// Brings up (or reuses) the "New Reminders" window with a bulk preview.
    func showBulkPreview(text: String) {
        let rootView = AnyView(
            BulkReminderPreview(text: text,
                                onCancel: { self.serviceWindow?.close() },
                                onDone: { self.serviceWindow?.close() })
                .environmentObject(store)
                .environmentObject(SettingsStore.shared)
        )
        if let hosting = serviceHosting {
            hosting.rootView = rootView
            serviceWindow?.makeKeyAndOrderFront(nil)
            applyAppearance(SettingsStore.shared.appearance)

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
        serviceWindow = window
        serviceHosting = hosting
        applyAppearance(SettingsStore.shared.appearance)
        NSApp.activate(ignoringOtherApps: true)
    }
}
