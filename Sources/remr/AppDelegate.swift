import AppKit
import Carbon.HIToolbox
import Combine
import EventKit
import SwiftUI

@MainActor
private final class FloatingKeyPanel: NSPanel {
    // Borderless windows do not become key by default. The text editor in the
    // quick-add surface needs the panel to accept keyboard input (including
    // Escape), while it must never become the application's main window.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Fixed height for the quick-add panel (clamped to the visible screen). The
/// description unfolds INSIDE this glass surface while typing — the window
/// never resizes, keeping the reveal motion identical to the in-app popover
/// and eliminating the resize-driven "bounce".
private let quickAddFixedHeight: CGFloat = 360

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
    private var calendarWindow: NSPanel?
    private var calendarHosting: NSHostingController<AnyView>?
    private var mouseDownGlobalMonitor: Any?
    private var mouseDownLocalMonitor: Any?
    private var quickAddCloseGeneration = 0
    private var calendarCloseGeneration = 0
    private var toggleHotKeyRef: EventHotKeyRef?
    private var quickAddHotKeyRef: EventHotKeyRef?
    private var calendarHotKeyRef: EventHotKeyRef?
    private let hotKeySignature: OSType = 0x72656D72 // "remr"
    private var currentToggleHotkeyCombo: KeyCombo?
    private var currentQuickAddHotkeyCombo: KeyCombo?
    private var currentCalendarHotkeyCombo: KeyCombo?
    private var hotKeyErrors: [BindableAction: String] = [:]
    private var settingsCancellables: Set<AnyCancellable> = []
    func applicationWillTerminate(_ notification: Notification) {
        if let toggleHotKeyRef { UnregisterEventHotKey(toggleHotKeyRef) }
        if let quickAddHotKeyRef { UnregisterEventHotKey(quickAddHotKeyRef) }
        if let calendarHotKeyRef { UnregisterEventHotKey(calendarHotKeyRef) }
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
                case 3: app.showCalendar()
                default: break
                }
            }
            return noErr
        }, 1, &eventType, nil, nil)
        reapplyHotKeys()
    }

    private func reapplyHotKeys(bindings: [BindableAction: KeyCombo]? = nil) {
        reapplyHotKey(.togglePopover, bindings: bindings)
        reapplyHotKey(.quickAdd, bindings: bindings)
        reapplyHotKey(.openCalendar, bindings: bindings)
    }

    /// Re-register one global binding without disturbing the other action's
    /// registration. A failed replacement restores this action's last working
    /// registration and reports the conflict through SettingsStore.
    private func reapplyHotKey(_ action: BindableAction,
                               bindings: [BindableAction: KeyCombo]? = nil) {
        let settings = SettingsStore.shared
        // Prefer the emitted dictionary: reading the store property inside a
        // sink would observe the pre-assignment value (@Published sends in
        // willSet) and re-register the previous hotkey.
        let combo = bindings?[action] ?? settings.combo(for: action)
        let current: KeyCombo?
        let ref: EventHotKeyRef?
        switch action {
        case .togglePopover:
            current = currentToggleHotkeyCombo
            ref = toggleHotKeyRef
        case .quickAdd:
            current = currentQuickAddHotkeyCombo
            ref = quickAddHotKeyRef
        case .openCalendar:
            current = currentCalendarHotkeyCombo
            ref = calendarHotKeyRef
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
        case .openCalendar:
            if let ref { UnregisterEventHotKey(ref) }
            calendarHotKeyRef = nil
            currentCalendarHotkeyCombo = nil
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
        case .openCalendar: return 3
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
        case .openCalendar:
            currentCalendarHotkeyCombo = combo
            calendarHotKeyRef = ref
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
            let settings = SettingsStore.shared
            StatusIcon.apply(to: button,
                             symbol: settings.menuBarIconSymbol,
                             style: settings.menuBarIconStyle,
                             color: settings.menuBarIconColor,
                             badge: settings.menuBarIconBadge,
                             count: 0)
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
        let hosting = NSHostingController(
            rootView: ContentView()
                .environmentObject(store)
                .environmentObject(SettingsStore.shared)
                .remrAppearance(using: SettingsStore.shared)
        )
        // Warm the first SwiftUI layout now, while the app is still settling
        // in behind the status item: the first popover show then appears
        // already laid out instead of rendering its initial tree on screen.
        // No window is attached, so onAppear/monitor installation stays idle.
        hosting.view.layoutSubtreeIfNeeded()
        popover.contentViewController = hosting
        popover.contentSize = NSSize(width: 400, height: 600)
        self.popover = popover

        mouseDownGlobalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.popover?.isShown == true { self.closePopover() }
                if self.quickAddWindow?.isVisible == true { self.closeQuickAdd() }
                if self.calendarWindow?.isVisible == true { self.closeCalendar() }
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
                guard let self else { return }
                if let w = self.quickAddWindow, w.isVisible, clickedWindowNumber != w.windowNumber { self.closeQuickAdd() }
                if let w = self.calendarWindow, w.isVisible, clickedWindowNumber != w.windowNumber { self.closeCalendar() }
            }
            return event
        }

        registerHotKey()

        SettingsStore.shared.$bindings
            .dropFirst()   // skip the initial value emission on subscribe
            .sink { [weak self] bindings in self?.reapplyHotKeys(bindings: bindings) }
            .store(in: &settingsCancellables)

        SettingsStore.shared.$appearance
            .sink { [weak self] appearance in self?.applyAppearance(appearance) }
            .store(in: &settingsCancellables)

        // Any of the icon settings re-renders the status item. The
        // emitted values are used rather than re-reading the store: @Published
        // sends in willSet, so reading the property inside a sink observes the
        // previous value and every change would lag by one. The store's first
        // refresh() publishes the counts shortly after launch, so the first
        // combined emission applies the badge; the manual initial apply above
        // is idempotent.
        SettingsStore.shared.$menuBarIconSymbol
            .combineLatest(SettingsStore.shared.$menuBarIconStyle,
                           SettingsStore.shared.$menuBarIconColor,
                           SettingsStore.shared.$menuBarIconBadge)
            .combineLatest(store.$overdueCount)
            .combineLatest(store.$dueTodayCount)
            .sink { [weak self] args, dueToday in
                guard let button = self?.statusItem?.button else { return }
                let (settings, overdue) = args
                let (symbol, style, color, badge) = settings
                StatusIcon.apply(to: button, symbol: symbol, style: style, color: color,
                                 badge: badge,
                                 count: badge == .overdue ? overdue : dueToday)
            }
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
        calendarWindow?.appearance = nsAppearance
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
            showPopover(relativeTo: button)
        }
    }

    private func showPopover(relativeTo button: NSStatusBarButton) {
        store.refresh()
        // Open instantly, then fade in. The native popover spring
        // (~0.25s) re-renders the Liquid Glass surface on every frame —
        // that per-frame glass work is what reads as "sluggish" on open.
        // Showing at full size and animating only the window alpha is a
        // single cheap layer composite, and it doubles as cover for the
        // initial list fill that lands right after show().
        popover.animates = false
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
        if let window = popover.contentViewController?.view.window {
            // Set the start alpha before the runloop paints so the first
            // composited frame is already transparent — no flash.
            window.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.1
                context.allowsImplicitAnimation = true
                window.animator().alphaValue = 1
            }
        }
        // Hardening: an .accessory app shown from the status item is not
        // activated by the status-item click alone, and local NSEvent
        // monitors only see hardware key events delivered to an active app.
        // Activating here guarantees the popover (and its inline Settings
        // view) receives keyboard input. Click-into-popover already
        // activates; this makes the popover keyboard-usable immediately.
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Closes the calendar and opens the main popover on a reminder's detail
    /// page (the calendar double-click handoff).
    func showReminderDetail(_ reminder: EKReminder) {
        closeCalendar()
        NotificationCenter.default.post(name: .remrShowReminderDetail,
                                        object: nil,
                                        userInfo: ["id": reminder.calendarItemIdentifier])
        if !popover.isShown, let button = statusItem.button {
            showPopover(relativeTo: button)
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

        // Invalidate any pending close fade from a previous presentation.
        quickAddCloseGeneration &+= 1
        let sessionID = UUID()

        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let fixedHeight = min(quickAddFixedHeight, (screen?.visibleFrame.height ?? 800) - 24)

        let rootView = AnyView(
            QuickAddView(sessionID: sessionID,
                         onCancel: { [weak self] in self?.closeQuickAdd() },
                         onCreated: { [weak self] in self?.closeQuickAdd() })
                .environmentObject(store)
                .environmentObject(SettingsStore.shared)
                .remrAppearance(using: SettingsStore.shared)
        )

        let window: NSPanel
        if let existingWindow = quickAddWindow, let hosting = quickAddHosting {
            hosting.rootView = rootView
            window = existingWindow
        } else {
            let hosting = NSHostingController(rootView: rootView)
            let newWindow = FloatingKeyPanel(contentViewController: hosting)
            newWindow.styleMask = [.borderless]
            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            // No window shadow: the panel is a transparent window whose only
            // opaque content is the glass card, so AppKit re-derives the
            // shadow from the card's shape every frame as it grows — that
            // re-computation reads as the liquid-glass "shimmy" at the top.
            newWindow.hasShadow = false
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

        // The panel is a fixed-size glass surface: the description unfolds
        // INSIDE it (pure SwiftUI, like the in-app popover), so the window
        // never moves or resizes while typing — that was the source of the
        // reveal "bounce". Sizing applies to reused windows too, so a reopen
        // always presents the same fixed panel.
        window.setContentSize(NSSize(width: 500, height: fixedHeight))

        // Restore the reusable panel before ordering it front. This keeps a
        // rapid reopen fully visible and invalidates any pending fade.
        window.alphaValue = 1

        if let screen {
            let visibleFrame = screen.visibleFrame
            let frame = window.frame
            window.setFrameOrigin(NSPoint(x: visibleFrame.midX - frame.width / 2,
                                          y: visibleFrame.midY - frame.height / 2))
        } else {
            window.center()
        }
        applyAppearance(SettingsStore.shared.appearance)
        // Activate BEFORE ordering front: the app is inactive when the global
        // hotkey fires, and an inactive app's window can never become key —
        // which is why autofocus never landed until the user clicked into the
        // panel. Ordering front after activation makes the panel key, so the
        // editor's focus request sticks.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
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

    /// Opens the calendar view in a reusable centered floating panel.
    func showCalendar() {
        if popover.isShown { closePopover() }

        // Invalidate any pending close fade from a previous presentation.
        calendarCloseGeneration &+= 1

        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens.first

        let rootView = AnyView(
            CalendarView(onCancel: { [weak self] in self?.closeCalendar() },
                         onOpenDetail: { [weak self] reminder in self?.showReminderDetail(reminder) })
                .environmentObject(store)
                .environmentObject(SettingsStore.shared)
                .remrAppearance(using: SettingsStore.shared)
        )

        let window: NSPanel
        if let existingWindow = calendarWindow, let hosting = calendarHosting {
            hosting.rootView = rootView
            window = existingWindow
        } else {
            let hosting = NSHostingController(rootView: rootView)
            let newWindow = FloatingKeyPanel(contentViewController: hosting)
            newWindow.styleMask = [.borderless]
            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            // No window shadow: the panel is a transparent window whose only
            // opaque content is the glass card, so AppKit re-derives the
            // shadow from the card's shape every frame — that
            // re-computation reads as the liquid-glass "shimmy" at the top.
            newWindow.hasShadow = false
            newWindow.isReleasedWhenClosed = false
            newWindow.isFloatingPanel = true
            newWindow.level = .floating
            newWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            newWindow.hidesOnDeactivate = false
            newWindow.becomesKeyOnlyIfNeeded = false
            calendarHosting = hosting
            calendarWindow = newWindow
            window = newWindow
        }

        // Fixed-size glass surface, clamped to the visible frame so the panel
        // never overflows smaller screens. Sizing applies to reused windows
        // too, so a reopen always presents the same panel.
        let width = min(880, (screen?.visibleFrame.width ?? 1200) - 24)
        let height = min(640, (screen?.visibleFrame.height ?? 800) - 24)
        window.setContentSize(NSSize(width: width, height: height))

        // Restore the reusable panel before ordering it front. This keeps a
        // rapid reopen fully visible and invalidates any pending fade.
        window.alphaValue = 1

        if let screen {
            let visibleFrame = screen.visibleFrame
            let frame = window.frame
            window.setFrameOrigin(NSPoint(x: visibleFrame.midX - frame.width / 2,
                                          y: visibleFrame.midY - frame.height / 2))
        } else {
            window.center()
        }
        applyAppearance(SettingsStore.shared.appearance)
        // Activate BEFORE ordering front: the app is inactive when shown from
        // the status item, and an inactive app's window can never become key.
        // Ordering front after activation makes the panel key, so keyboard
        // input (Esc, mode switching) works immediately.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func closeCalendar() {
        guard let window = calendarWindow else { return }
        guard window.isVisible else {
            window.alphaValue = 1
            return
        }

        calendarCloseGeneration &+= 1
        let generation = calendarCloseGeneration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.allowsImplicitAnimation = true
            window.animator().alphaValue = 0
        } completionHandler: { [weak self, weak window] in
            MainActor.assumeIsolated {
                guard let self, let window,
                      self.calendarCloseGeneration == generation else { return }
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
        if calendarWindow?.isVisible == true { closeCalendar() }
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
                .remrAppearance(using: SettingsStore.shared)
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
