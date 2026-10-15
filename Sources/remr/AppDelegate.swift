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

    // The notch panel deliberately runs up behind the menu bar and notch, so
    // it must not be pushed back down into the visible frame.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// The first click after switching apps acts on the control beneath it.
private final class FirstMouseHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
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
    /// Borderless presentation of the main content at the top centre of the
    /// main display, used when the notch setting is on. An NSPopover always
    /// draws its arrow, so a plain floating panel is the only way to get an
    /// arrow-less surface flush with the top.
    private var notchWindow: FloatingKeyPanel?
    private var notchHosting: FirstMouseHostingView?
    private var notchContentLayout = NSSize.zero
    private var notchCloseGeneration = 0
    /// Drives the notch panel's open reveal (reset and re-triggered per show).
    private let notchReveal = NotchRevealController()
    private var reviewNudgeController: ReviewNudgeController?
    private var serviceWindow: NSWindow?
    private var serviceHosting: NSHostingController<AnyView>?
    private var quickAddWindow: NSPanel?
    private var quickAddHosting: NSHostingController<AnyView>?
    private var calendarWindow: NSPanel?
    private var calendarHosting: FirstMouseHostingView?
    private let calendarReveal = NotchRevealController(duration: 0.22, contentFadeDuration: 0.08)
    private struct CalendarPanelLayout: Equatable {
        let size: NSSize
        let topInset: CGFloat
        let housingWidth: CGFloat
    }
    private var calendarContentLayout: CalendarPanelLayout?
    private var pomodoroCompletionWindow: NSPanel?
    private var pomodoroCompletionHosting: NSHostingController<AnyView>?
    private var voiceDictationWindow: NSPanel?
    private var voiceDictationHosting: NSHostingController<AnyView>?
    private lazy var voiceCoordinator: VoiceDictationCoordinator = {
        let transcriber = AppleSpeechTranscriber(inputDeviceID: SettingsStore.shared.voiceInputDeviceID)
        let coordinator = VoiceDictationCoordinator(transcriber: transcriber)
        coordinator.onCompleted = { [weak self] mode, transcript, cleaned in
            self?.handleVoiceCompletion(mode: mode, transcript: transcript, cleaned: cleaned)
        }
        return coordinator
    }()
    private var mouseDownGlobalMonitor: Any?
    private var mouseDownLocalMonitor: Any?
    private var keyDownLocalMonitor: Any?
    private var calendarHeldKeys: Set<UInt16> = []
    private var quickAddCloseGeneration = 0
    private var calendarCloseGeneration = 0
    private var toggleHotKeyRef: EventHotKeyRef?
    private var quickAddHotKeyRef: EventHotKeyRef?
    private var calendarHotKeyRef: EventHotKeyRef?
    private var voiceVerifyHotKeyRef: EventHotKeyRef?
    private var voiceLogHotKeyRef: EventHotKeyRef?
    private let hotKeySignature: OSType = 0x72656D72 // "remr"
    private var currentToggleHotkeyCombo: KeyCombo?
    private var currentQuickAddHotkeyCombo: KeyCombo?
    private var currentCalendarHotkeyCombo: KeyCombo?
    private var currentVoiceVerifyHotkeyCombo: KeyCombo?
    private var currentVoiceLogHotkeyCombo: KeyCombo?
    private var hotKeyErrors: [BindableAction: String] = [:]
    private var settingsCancellables: Set<AnyCancellable> = []
    private var pomodoroMenuBarTitle: String?
    func applicationWillTerminate(_ notification: Notification) {
        reviewNudgeController?.dismiss()
        reviewNudgeController = nil
        if let toggleHotKeyRef { UnregisterEventHotKey(toggleHotKeyRef) }
        if let quickAddHotKeyRef { UnregisterEventHotKey(quickAddHotKeyRef) }
        if let calendarHotKeyRef { UnregisterEventHotKey(calendarHotKeyRef) }
        if let voiceVerifyHotKeyRef { UnregisterEventHotKey(voiceVerifyHotKeyRef) }
        if let voiceLogHotKeyRef { UnregisterEventHotKey(voiceLogHotKeyRef) }
        voiceCoordinator.cancel()
        if let mouseDownGlobalMonitor {
            NSEvent.removeMonitor(mouseDownGlobalMonitor)
            self.mouseDownGlobalMonitor = nil
        }
        if let mouseDownLocalMonitor {
            NSEvent.removeMonitor(mouseDownLocalMonitor)
            self.mouseDownLocalMonitor = nil
        }
        if let keyDownLocalMonitor {
            NSEvent.removeMonitor(keyDownLocalMonitor)
            self.keyDownLocalMonitor = nil
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
                case 4 where SettingsStore.shared.ollamaEnabled: app.toggleVoice(mode: .verify)
                case 5 where SettingsStore.shared.ollamaEnabled: app.toggleVoice(mode: .log)
                default: break
                }
            }
            return noErr
        }, 1, &eventType, nil, nil)
        reapplyHotKeys()
    }

    private func reapplyHotKeys(bindings: [BindableAction: KeyCombo]? = nil,
                                 localModelEnabled: Bool? = nil) {
        reapplyHotKey(.togglePopover, bindings: bindings)
        reapplyHotKey(.quickAdd, bindings: bindings)
        reapplyHotKey(.openCalendar, bindings: bindings)
        let voiceBindings: [BindableAction: KeyCombo]? =
            (localModelEnabled ?? SettingsStore.shared.ollamaEnabled)
            ? bindings
            : [.voiceVerify: KeyCombo([]), .voiceLog: KeyCombo([])]
        reapplyHotKey(.voiceVerify, bindings: voiceBindings)
        reapplyHotKey(.voiceLog, bindings: voiceBindings)
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
        case .voiceVerify:
            current = currentVoiceVerifyHotkeyCombo
            ref = voiceVerifyHotKeyRef
        case .voiceLog:
            current = currentVoiceLogHotkeyCombo
            ref = voiceLogHotKeyRef
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
        case .voiceVerify:
            if let ref { UnregisterEventHotKey(ref) }
            voiceVerifyHotKeyRef = nil
            currentVoiceVerifyHotkeyCombo = nil
        case .voiceLog:
            if let ref { UnregisterEventHotKey(ref) }
            voiceLogHotKeyRef = nil
            currentVoiceLogHotkeyCombo = nil
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
            let message = "The global shortcut needs exactly one key (e.g. ⌥Space)"
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
        case .voiceVerify: return 4
        case .voiceLog: return 5
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
        case .voiceVerify:
            currentVoiceVerifyHotkeyCombo = combo
            voiceVerifyHotKeyRef = ref
        case .voiceLog:
            currentVoiceLogHotkeyCombo = combo
            voiceLogHotKeyRef = ref
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

        // The calendar's first render is expensive enough to stall its
        // reveal; paint it once while hidden, shortly after launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.warmCalendarContent()
        }

        // REMR-POMO-PROBE-BEGIN
        PomodoroKeyProbe.startDriverIfRequested()
        // REMR-POMO-PROBE-END

        // REMR-MORPH-PROBE-BEGIN
        CalendarMorphProbe.startIfRequested()
        // REMR-MORPH-PROBE-END

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
                .environmentObject(VoiceLogStore.shared)
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

        // Warm the notch panel too when it is the chosen surface, so its
        // notification subscriptions are live before the first open.
        if SettingsStore.shared.notchPopover {
            prepareNotchContent()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, !self.isMainSurfaceShown, self.calendarWindow?.isVisible != true else { return }
            self.prepareCalendarContent()
        }

        mouseDownGlobalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.isMainSurfaceShown { self.closePopover() }
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

        // Calendar keyboard controls share the main view's routing and focus
        // guards. Track full chords so custom local bindings work in both views.
        keyDownLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            guard let window = self.calendarWindow,
                  window.isVisible,
                  event.window?.windowNumber == window.windowNumber else {
                self.calendarHeldKeys.removeAll()
                return event
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let modifiers: [(ModifierKey, NSEvent.ModifierFlags)] = [
                (.command, .command), (.option, .option), (.control, .control), (.shift, .shift)
            ]
            for (modifier, flag) in modifiers {
                if flags.contains(flag) { self.calendarHeldKeys.insert(modifier.keyCode) }
                else { self.calendarHeldKeys.remove(modifier.keyCode) }
            }
            if event.type == .flagsChanged { return event }
            let key = ModifierKey.canonicalKeyCode(for: event.keyCode) ?? event.keyCode
            if event.type == .keyUp {
                self.calendarHeldKeys.remove(key)
                return event
            }
            self.calendarHeldKeys.insert(key)
            guard !SettingsStore.shared.isCapturing else { return event }
            if event.keyCode == 53 {
                self.closeCalendar()
                return nil
            }
            let responder = window.firstResponder
            let context = KeyboardContext(
                textFieldFocused: responder is NSTextView || window.attachedSheet != nil,
                searchFieldFocused: responder is NSTextField,
                selectionIsHeader: false, hasSelection: false, searchHasText: false,
                selectionIsReminder: false, selectionIsCompleted: false, hasUndo: false,
                calendarPresented: true)
            guard KeyboardRouter.action(keyCode: event.keyCode, heldKeyCodes: self.calendarHeldKeys,
                                        context: context, bindings: SettingsStore.shared.bindings) == .showMainReminders
            else { return event }
            if !event.isARepeat { self.returnToMainFromCalendar() }
            return nil
        }

        registerHotKey()

        SettingsStore.shared.$bindings
            .dropFirst()   // skip the initial value emission on subscribe
            .sink { [weak self] bindings in self?.reapplyHotKeys(bindings: bindings) }
            .store(in: &settingsCancellables)

        SettingsStore.shared.$ollamaEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                self?.reapplyHotKeys(localModelEnabled: enabled)
            }
            .store(in: &settingsCancellables)

        SettingsStore.shared.$appearance
            .sink { [weak self] appearance in self?.applyAppearance(appearance) }
            .store(in: &settingsCancellables)

        // Switching between the menu-bar-anchored popover and the top-centre
        // panel changes which surface a shown popover uses, so dismiss the
        // current one and let the next open pick up the new mode.
        SettingsStore.shared.$notchPopover
            .dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                if self.isMainSurfaceShown { self.closePopover() }
                if enabled { self.prepareNotchContent() }
            }
            .store(in: &settingsCancellables)

        // A width change is applied to the open panel immediately: rebuild the
        // content at the new width, then resize and re-centre the window.
        SettingsStore.shared.$notchPanelWidth
            .dropFirst()
            .sink { [weak self] width in
                guard let self, let window = self.notchWindow, window.isVisible else { return }
                self.prepareNotchContent(width: width)
                window.setContentSize(NSSize(width: width, height: window.frame.height))
                self.positionNotchWindow(window)
            }
            .store(in: &settingsCancellables)

        PomodoroTimerStore.shared.$completion
            .compactMap { $0 }
            .sink { [weak self] completion in
                self?.showPomodoroCompletion(completion)
            }
            .store(in: &settingsCancellables)
        if SettingsStore.shared.pomodoroEnabled,
           let completion = PomodoroTimerStore.shared.completion {
            showPomodoroCompletion(completion)
        }

        SettingsStore.shared.$pomodoroEnabled
            .dropFirst()
            .filter { !$0 }
            .sink { [weak self] _ in
                PomodoroTimerStore.shared.pause()
                PomodoroTimerStore.shared.clearCompletion()
                self?.closePomodoroCompletion()
            }
            .store(in: &settingsCancellables)

        PomodoroTimerStore.shared.$menuBarTitle
            .removeDuplicates()
            .sink { [weak self] title in
                self?.pomodoroMenuBarTitle = title
                self?.updateStatusItem()
            }
            .store(in: &settingsCancellables)

        // Deliver after @Published's willSet so restoring the icon always uses
        // the latest appearance and badge counts, including changes made while
        // the countdown occupied the button.
        Publishers.MergeMany([
            SettingsStore.shared.$menuBarIconSymbol.map { _ in () }.eraseToAnyPublisher(),
            SettingsStore.shared.$menuBarIconStyle.map { _ in () }.eraseToAnyPublisher(),
            SettingsStore.shared.$menuBarIconColor.map { _ in () }.eraseToAnyPublisher(),
            SettingsStore.shared.$menuBarIconBadge.map { _ in () }.eraseToAnyPublisher(),
            SettingsStore.shared.$pomodoroEnabled.map { _ in () }.eraseToAnyPublisher(),
            store.$overdueCount.map { _ in () }.eraseToAnyPublisher(),
            store.$dueTodayCount.map { _ in () }.eraseToAnyPublisher()
        ])
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.updateStatusItem() }
            .store(in: &settingsCancellables)

        reviewNudgeController = ReviewNudgeController(
            store: store, settings: SettingsStore.shared,
            isBusy: { [weak self] in
                guard let self else { return true }
                return self.isMainSurfaceShown || self.quickAddWindow?.isVisible == true
                    || self.calendarWindow?.isVisible == true || self.serviceWindow?.isVisible == true
                    || self.voiceDictationWindow?.isVisible == true || self.pomodoroCompletionWindow?.isVisible == true
            }, onReview: { [weak self] in
                guard let self, let button = self.statusItem.button else { return }
                self.showPopover(relativeTo: button)
            })
    }

    func previewReviewNudge() {
        if isMainSurfaceShown { closePopover() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, !self.isMainSurfaceShown else { return }
            self.reviewNudgeController?.preview()
        }
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
        pomodoroCompletionWindow?.appearance = nsAppearance
        voiceDictationWindow?.appearance = nsAppearance
    }


    // MARK: - Status item

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let settings = SettingsStore.shared
        if settings.pomodoroEnabled, let title = pomodoroMenuBarTitle {
            button.image = nil
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.title = title
            button.toolTip = "remr — \(PomodoroTimerStore.shared.phase.title) \(title) remaining"
            button.setAccessibilityLabel(button.toolTip)
        } else {
            button.title = ""
            button.toolTip = "remr"
            button.setAccessibilityLabel("remr")
            StatusIcon.apply(to: button,
                             symbol: settings.menuBarIconSymbol,
                             style: settings.menuBarIconStyle,
                             color: settings.menuBarIconColor,
                             badge: settings.menuBarIconBadge,
                             count: settings.menuBarIconBadge == .overdue ? store.overdueCount : store.dueTodayCount)
        }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            // A status-item menu is its own window; close the popover first
            // so the two don't stack.
            if isMainSurfaceShown { closePopover() }
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

    /// Whether the main content is currently on screen, whichever surface is
    /// presenting it.
    private var isMainSurfaceShown: Bool {
        popover.isShown || (notchWindow?.isVisible ?? false)
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if isMainSurfaceShown {
            closePopover()
        } else {
            showPopover(relativeTo: button)
        }
    }

    private func showPopover(relativeTo button: NSStatusBarButton) {
        closeCalendar(animated: false)
        reviewNudgeController?.didReview()
        if SettingsStore.shared.notchPopover {
            showNotchPanel()
        } else {
            showButtonAnchoredPopover(relativeTo: button)
        }
    }

    func showMainReminders() {
        guard let button = statusItem.button else { return }
        showPopover(relativeTo: button)
    }

    // REMR-POMO-PROBE-BEGIN
    func probeShowMainSurface() {
        if !isMainSurfaceShown, let button = statusItem.button {
            showPopover(relativeTo: button)
            PomodoroKeyProbe.log("driver:surface shown route=\(SettingsStore.shared.notchPopover ? "notch" : "popover") notchVisible=\(notchWindow?.isVisible ?? false) keyWindow=\(NSApp.keyWindow.map { "#\($0.windowNumber) \(type(of: $0))" } ?? "nil")")
        } else {
            PomodoroKeyProbe.log("driver:surface already shown or no button")
        }
    }

    var probeMainSurfaceState: String {
        "shown=\(isMainSurfaceShown) notchVisible=\(notchWindow?.isVisible ?? false) active=\(NSApp.isActive)"
    }
    // REMR-POMO-PROBE-END

    // REMR-MORPH-PROBE-BEGIN
    var probeNotchWindow: NSWindow? { notchWindow }
    var probeCalendarWindow: NSWindow? { calendarWindow }
    var probeCalendarHosting: NSView? { calendarHosting }
    var probeCalendarReveal: NotchRevealController { calendarReveal }

    /// Forces the calendar tree's first real render while the window is
    /// invisible, so the probe can tell a cold first paint from the morph.
    func probeWarmCalendar() {
        warmCalendarContent()
    }
    // REMR-MORPH-PROBE-END

    private func showButtonAnchoredPopover(relativeTo button: NSStatusBarButton) {
        store.refresh()
        // Open instantly, then fade in. The native popover spring
        // (~0.25s) re-renders the Liquid Glass surface on every frame —
        // that per-frame glass work is what reads as "sluggish" on open.
        // Showing at full size and animating only the window alpha is a
        // single cheap layer composite, and it doubles as cover for the
        // initial list fill that lands right after show().
        let collapsedHeight = MainPopoverLayout.height(pomodoroEnabled: SettingsStore.shared.pomodoroEnabled)
        popover.contentSize = NSSize(width: 400, height: collapsedHeight)
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

    /// Opens the main content in a borderless panel centred at the top of the
    /// main display. An NSPopover always renders its arrow, so an arrow-less
    /// surface flush with the top can only be a plain floating panel.
    private func showNotchPanel() {
        if popover.isShown { closePopover() }
        prepareNotchContent()

        // Invalidate any pending close fade from a previous presentation.
        notchCloseGeneration &+= 1
        let generation = notchCloseGeneration
        // Start collapsed so the window's first visible frame is the notch
        // strip, not the full panel.
        notchReveal.reset()

        guard let window = notchWindow else { return }
        let collapsedHeight: CGFloat = MainPopoverLayout.height(pomodoroEnabled: SettingsStore.shared.pomodoroEnabled)
        window.alphaValue = 1
        window.setContentSize(NSSize(width: SettingsStore.shared.notchPanelWidth,
                                     height: collapsedHeight + notchTopInset))
        positionNotchWindow(window)

        applyAppearance(SettingsStore.shared.appearance)
        // Activate before ordering front so an inactive app can still make the
        // panel key and receive keyboard input immediately.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // REMR-POMO-PROBE-BEGIN
        PomodoroKeyProbe.log("showNotchPanel ordered isVisible=\(window.isVisible) isKey=\(window.isKeyWindow) appActive=\(NSApp.isActive)")
        // REMR-POMO-PROBE-END

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            notchReveal.open(animated: false)
            store.refresh()
        } else {
            provideNotchHaptic()
            // The glass and its rim finish opening together in 280 ms.
            // Keep reminders hidden until that movement is complete.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.notchWindow?.isVisible == true,
                      self.notchCloseGeneration == generation else { return }
                self.notchReveal.open(animated: true)
                // Fetching publishes whole reminder arrays and rebuilds the
                // list. Keep that burst out of the glass animation's frames.
                DispatchQueue.main.asyncAfter(deadline: .now() + NotchRevealController.openingDuration) { [weak self] in
                    guard let self, self.notchWindow?.isVisible == true,
                          self.notchCloseGeneration == generation else { return }
                    self.store.refresh()
                }
            }
        }
    }

    /// A gentle trackpad tap as the panel opens, like the notch islands use.
    /// Silent on hardware without a Force Touch trackpad.
    private func provideNotchHaptic() {
        guard SettingsStore.shared.notchHapticEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }

    /// The display the notch panel lives on: the primary (menu bar) display.
    private func notchScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    /// Height of the menu bar / notch area at the top of the primary display.
    /// The panel extends up through this so its surface reaches the screen
    /// edge, while the content stays below it.
    private var notchTopInset: CGFloat {
        guard let screen = notchScreen() else { return 0 }
        let menuBar = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        // A notched Mac keeps its reserved strip even when the menu bar is
        // auto-hidden, and `visibleFrame` stops accounting for it — which would
        // drop the content under the cutout. The auxiliary areas describe the
        // region either side of the notch, so their top edge gives the notch
        // height directly.
        let notch = screen.auxiliaryTopLeftArea.map { max(0, screen.frame.maxY - $0.minY) } ?? 0
        return max(menuBar, notch, screen.safeAreaInsets.top)
    }

    private var notchHousingWidth: CGFloat {
        guard let screen = notchScreen(),
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else { return 172 }
        return max(1, right.minX - left.maxX)
    }

    /// Builds the notch panel's content. Kept in one place so the eagerly
    /// warmed view and a lazily created one are identical.
    private func notchRootView(width: CGFloat) -> AnyView {
        let inset = notchTopInset
        let shoulder = NotchPanelShape.topShoulder
        return AnyView(
            // The content is inset by the shoulder on each side so the
            // silhouette's flare never clips it; the window keeps the full
            // configured width.
            ContentView(surface: .floatingPanel,
                        width: max(0, width - shoulder * 2),
                        topInset: inset,
                        horizontalInset: shoulder,
                        notchReveal: notchReveal,
                        notchCollapsedWidth: notchHousingWidth)
                .environmentObject(store)
                .environmentObject(SettingsStore.shared)
                .environmentObject(VoiceLogStore.shared)
                .remrAppearance(using: SettingsStore.shared)
        )
    }

    /// Creates (and warms) the notch panel eagerly, so its content view is
    /// mounted and its notification subscriptions are live before the first
    /// open. Without this, a hand-off that posts before the panel is first
    /// shown — the calendar's double-click detail, or a bulk preview from
    /// voice — would reach no one, exactly as the popover is warmed at launch.
    private func prepareNotchContent(width requestedWidth: CGFloat? = nil) {
        let width = requestedWidth ?? SettingsStore.shared.notchPanelWidth
        let layout = NSSize(width: width, height: notchTopInset)
        guard notchHosting == nil || notchContentLayout != layout else { return }
        notchContentLayout = layout
        if let hosting = notchHosting {
            hosting.rootView = notchRootView(width: width)
            return
        }
        let hosting = FirstMouseHostingView(rootView: notchRootView(width: width))
        // Size and position are driven from here, never derived from the
        // content, so a width or Pomodoro change is the only thing that moves
        // the window.
        hosting.sizingOptions = []
        // Warm the first layout while no window is attached, so onAppear and
        // the focus monitors stay idle until the panel is actually shown.
        hosting.layoutSubtreeIfNeeded()
        let window = FloatingKeyPanel(contentRect: .zero,
                                      styleMask: [.borderless],
                                      backing: .buffered,
                                      defer: false)
        window.contentView = hosting
        window.isOpaque = false
        window.backgroundColor = .clear
        // No window shadow: the only opaque content is the glass card, so
        // AppKit would re-derive the shadow from the card's shape every time it
        // resizes (the Pomodoro section), which reads as a shimmy — the same
        // reason the other floating panels drop it.
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.isFloatingPanel = true
        // Above the menu bar (and the notch), so the panel's black bleed merges
        // with the housing instead of being cut through by the menu bar.
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = false
        notchHosting = hosting
        notchWindow = window
    }

    /// Centres the notch panel horizontally on the primary display with its
    /// top edge at the very top of the screen, so the surface runs up behind
    /// the menu bar and notch and reads as dropping from the top.
    private func positionNotchWindow(_ window: NSWindow) {
        guard let screen = notchScreen() else {
            window.center()
            return
        }
        let frame = window.frame
        window.setFrameOrigin(NSPoint(x: screen.frame.midX - frame.width / 2,
                                      y: screen.frame.maxY - frame.height))
    }

    /// Closes the calendar and opens the main popover on a reminder's detail
    /// page (the calendar double-click handoff).
    func showReminderDetail(_ reminder: EKReminder) {
        closeCalendar(animated: false)
        NotificationCenter.default.post(name: .remrShowReminderDetail,
                                        object: nil,
                                        userInfo: ["id": reminder.calendarItemIdentifier])
        if !isMainSurfaceShown, let button = statusItem.button {
            showPopover(relativeTo: button)
        }
    }

    /// Fade the popover window out, then close it. Used everywhere the
    /// popover dismisses. The native animation is enabled for opening, but is
    /// disabled around `performClose` so this custom fade remains the only
    /// close transition.
    func closePopover() {
        if notchWindow?.isVisible == true {
            closeNotchPanel()
            return
        }
        guard popover.isShown, let window = popover.contentViewController?.view.window else { return }
        NotificationCenter.default.post(name: .remrPopoverClosing, object: nil)
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

    /// Withdraw the content, then retract the glass into the camera housing.
    /// A generation guard keeps a quick reopen from being ordered off screen.
    private func closeNotchPanel(animated: Bool = true) {
        guard let window = notchWindow, window.isVisible else {
            notchWindow?.alphaValue = 1
            return
        }
        notchCloseGeneration &+= 1
        let generation = notchCloseGeneration
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduceMotion || !animated {
            window.orderOut(nil)
            notchReveal.reset()
            NotificationCenter.default.post(name: .remrPopoverClosing, object: nil)
            return
        }
        notchReveal.retract()
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchRevealController.closingDuration) { [weak self, weak window] in
            guard let self, let window,
                  self.notchCloseGeneration == generation else { return }
            window.orderOut(nil)
            self.notchReveal.reset()
            // Reset expanding sections only after the glass is off screen;
            // changing its window height during retraction would move the rim.
            NotificationCenter.default.post(name: .remrPopoverClosing, object: nil)
        }
    }

    /// Fades the reminders panel out beneath the calendar, which starts at
    /// exactly this panel's silhouette and covers it as it expands. Only the
    /// window alpha changes — retracting the shape as well would show its rim
    /// moving under the opening glass.
    ///
    /// The fade is deliberately much shorter than the calendar's expansion:
    /// matching the two durations turned the handoff into a cross-fade that
    /// read as "the panel closes and a calendar appears". A quick handoff
    /// leaves the shape looking stationary while the glass swaps, so the
    /// expansion that follows is what the eye reads.
    private func fadeOutNotchPanelForCalendar() {
        guard let window = notchWindow, window.isVisible else { return }
        notchCloseGeneration &+= 1
        let generation = notchCloseGeneration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            context.allowsImplicitAnimation = true
            window.animator().alphaValue = 0
        } completionHandler: { [weak self, weak window] in
            MainActor.assumeIsolated {
                guard let self, let window,
                      self.notchCloseGeneration == generation else { return }
                window.orderOut(nil)
                window.alphaValue = 1
                self.notchReveal.reset()
                NotificationCenter.default.post(name: .remrPopoverClosing, object: nil)
            }
        }
    }

    /// Opens a fresh quick-add session in a reusable centered floating panel.
    func showQuickAdd() {
        if isMainSurfaceShown { closePopover() }

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

    func toggleVoice(mode: VoiceDictationMode) {
        voiceCoordinator.configure(inputDeviceID: SettingsStore.shared.voiceInputDeviceID)
        switch voiceCoordinator.state {
        case .recording:
            // Keep the panel open through processing: success closes it via
            // handleVoiceCompletion, failure now stays visible with Retry
            // (closing here hid log-mode failures entirely).
            voiceCoordinator.stop()
        case .processing:
            break
        case .idle, .failed:
            showVoicePanel(mode: mode)
            voiceCoordinator.start(mode: mode)
        }
    }

    private func showVoicePanel(mode: VoiceDictationMode) {
        if isMainSurfaceShown { closePopover() }
        let root = AnyView(
            VoiceDictationView(coordinator: voiceCoordinator,
                               onCancel: { [weak self] in self?.cancelVoice() })
                .remrAppearance(using: SettingsStore.shared)
        )
        let window: NSPanel
        if let existing = voiceDictationWindow, let hosting = voiceDictationHosting {
            hosting.rootView = root
            window = existing
        } else {
            let hosting = NSHostingController(rootView: root)
            let panel = FloatingKeyPanel(contentViewController: hosting)
            panel.styleMask = [.borderless]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isReleasedWhenClosed = false
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            voiceDictationHosting = hosting
            voiceDictationWindow = panel
            window = panel
        }
        window.setContentSize(NSSize(width: 360, height: 245))
        window.alphaValue = 1
        if let button = statusItem?.button,
           let screenRect = button.window?.convertToScreen(button.bounds) {
            let frame = window.frame
            window.setFrameOrigin(NSPoint(x: screenRect.midX - frame.width / 2,
                                          y: screenRect.minY - frame.height - 8))
        } else {
            window.center()
        }
        applyAppearance(SettingsStore.shared.appearance)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func cancelVoice() {
        voiceCoordinator.cancel()
        voiceDictationWindow?.orderOut(nil)
    }

    private func closeVoice() {
        voiceDictationWindow?.orderOut(nil)
    }

    private func handleVoiceCompletion(mode: VoiceDictationMode,
                                       transcript: String,
                                       cleaned: String) {
        closeVoice()
        if mode == .log {
            VoiceLogStore.shared.append(transcript: transcript, cleaned: cleaned)
        } else {
            showBulkInPopover(text: cleaned)
        }
    }

    /// Opens cleaned text in the main popover's verify-and-edit list — the
    /// same BulkReminderPreview bulk import uses — instead of a second window.
    func showBulkInPopover(text: String) {
        voiceDictationWindow?.orderOut(nil)
        if quickAddWindow?.isVisible == true { closeQuickAdd() }
        if calendarWindow?.isVisible == true { closeCalendar() }
        if !isMainSurfaceShown, let button = statusItem.button {
            showPopover(relativeTo: button)
        } else {
            store.refresh()
            NSApp.activate(ignoringOtherApps: true)
        }
        NotificationCenter.default.post(name: .remrShowBulkPreview,
                                        object: nil,
                                        userInfo: ["text": text])
    }

    /// Updates the surface height when the optional Pomodoro footer is enabled or disabled.
    func setPopoverHeight(_ height: CGFloat, animated: Bool = false) {
        if let notchWindow, notchWindow.isVisible {
            setNotchHeight(height, animated: animated)
            return
        }
        let window = popover.contentViewController?.view.window
        let centerX = window?.frame.midX
        let size = NSSize(width: popover.contentSize.width,
                          height: max(0, height))

        let applyOrigin = {
            guard let window, let centerX else { return }
            let frame = window.frame
            window.setFrameOrigin(NSPoint(x: centerX - frame.width / 2,
                                          y: frame.minY))
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window?.animator().setContentSize(size)
            } completionHandler: {
                applyOrigin()
            }
        } else {
            popover.contentSize = size
            applyOrigin()
        }
    }

    /// Resizes the notch panel while keeping its top edge pinned and its
    /// horizontal centre fixed, so it appears to grow downward from the notch.
    private func setNotchHeight(_ height: CGFloat, animated: Bool) {
        guard let window = notchWindow else { return }
        let topY = window.frame.maxY
        let x = window.frame.minX
        let size = NSSize(width: window.frame.width, height: max(0, height) + notchTopInset)
        let frame = NSRect(x: x, y: topY - size.height, width: size.width, height: size.height)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(frame, display: true)
            }
        } else {
            window.setFrame(frame, display: true)
        }
    }

    private func showPomodoroCompletion(_ completion: PomodoroCompletion) {
        let timer = PomodoroTimerStore.shared
        let rootView = AnyView(
            PomodoroCompletionView(
                phase: completion.phase,
                nextPhase: timer.nextPhase,
                onStartNext: { [weak self] in
                    timer.startNextPhase()
                    self?.closePomodoroCompletion()
                },
                onDismiss: { [weak self] in
                    timer.clearCompletion()
                    self?.closePomodoroCompletion()
                }
            )
            .remrAppearance(using: SettingsStore.shared)
        )

        let window: NSPanel
        if let existingWindow = pomodoroCompletionWindow,
           let hosting = pomodoroCompletionHosting {
            hosting.rootView = rootView
            window = existingWindow
        } else {
            let hosting = NSHostingController(rootView: rootView)
            let newWindow = FloatingKeyPanel(contentViewController: hosting)
            newWindow.styleMask = [.borderless]
            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            newWindow.hasShadow = false
            newWindow.isReleasedWhenClosed = false
            newWindow.isFloatingPanel = true
            newWindow.level = .floating
            newWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            newWindow.hidesOnDeactivate = false
            newWindow.becomesKeyOnlyIfNeeded = true
            pomodoroCompletionHosting = hosting
            pomodoroCompletionWindow = newWindow
            window = newWindow
        }

        window.setContentSize(NSSize(width: 376, height: 220))
        window.alphaValue = 1
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        if let screen {
            let visibleFrame = screen.visibleFrame
            let frame = window.frame
            window.setFrameOrigin(NSPoint(x: visibleFrame.maxX - frame.width - 24,
                                          y: visibleFrame.maxY - frame.height - 24))
        } else {
            window.center()
        }
        applyAppearance(SettingsStore.shared.appearance)
        NSSound(named: NSSound.Name("Tink"))?.play()
        window.orderFrontRegardless()
    }

    private func closePomodoroCompletion() {
        pomodoroCompletionWindow?.orderOut(nil)
    }

    /// Opens Remr's calendar from a URL, including when called by Raycast.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "remr" && $0.host == "calendar" }) else { return }
        showCalendar()
    }

    /// Prepare the fixed calendar tree and its day cells while the window is
    /// hidden, then reuse them on each open rather than laying out during reveal.
    private func prepareCalendarContent() {
        let screen = notchScreen()
        let inset = notchTopInset
        let shoulder = NotchPanelShape.topShoulder
        let availableWidth = max(320, (screen?.visibleFrame.width ?? 1440) - 24)
        let availableHeight = max(320, (screen?.visibleFrame.height ?? 900) - 24)
        let width = min(1200, availableWidth * 0.75)
        let contentHeight = min(1100, availableHeight)
        let size = NSSize(width: width, height: contentHeight + inset)
        let layout = CalendarPanelLayout(size: size, topInset: inset, housingWidth: notchHousingWidth)

        guard calendarHosting == nil || calendarContentLayout != layout else { return }
        let rootView = AnyView(
            CalendarView(reveal: calendarReveal, onCancel: { [weak self] in self?.closeCalendar() },
                         onOpenDetail: { [weak self] reminder in self?.showReminderDetail(reminder) })
                .frame(width: max(0, width - shoulder * 2), height: contentHeight)
                .notchContentReveal(calendarReveal)
                .padding(.top, inset)
                .padding(.horizontal, shoulder)
                .liquidGlassNotchPanel(headHeight: inset, reveal: calendarReveal,
                                      collapsedWidth: notchHousingWidth, defersGlassUntilOpen: true)
                .environmentObject(store)
                .environmentObject(SettingsStore.shared)
                .remrAppearance(using: SettingsStore.shared)
        )
        if let hosting = calendarHosting {
            hosting.rootView = rootView
        } else {
            let hosting = FirstMouseHostingView(rootView: rootView)
            hosting.sizingOptions = []
            let window = FloatingKeyPanel(contentRect: NSRect(origin: .zero, size: size),
                                          styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.isFloatingPanel = true
            window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.hidesOnDeactivate = false
            window.becomesKeyOnlyIfNeeded = false
            calendarHosting = hosting
            calendarWindow = window
        }
        calendarContentLayout = layout

        guard let window = calendarWindow else { return }
        window.setContentSize(size)
        calendarHosting?.layoutSubtreeIfNeeded()
    }

    /// Builds and paints the calendar tree once while its window is
    /// invisible. `prepareCalendarContent` warms layout, but the first real
    /// render — glass, text, the day grid — is expensive; when it first
    /// happens on screen it stalls the reveal for hundreds of milliseconds,
    /// so the expansion jumps instead of animating. Paying that cost up
    /// front, with the window transparent, keeps the opening smooth.
    private func warmCalendarContent() {
        prepareCalendarContent()
        guard let window = calendarWindow, let hosting = calendarHosting,
              !window.isVisible else { return }
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        DispatchQueue.main.async { [weak window] in
            window?.orderOut(nil)
            window?.alphaValue = 1
        }
    }

    /// Opens the calendar with the same glass reveal as the reminders panel.
    /// When that panel is on screen the calendar grows out of its silhouette
    /// instead of re-opening from the notch: the two surfaces read as one
    /// shape changing form. Layout stays fixed throughout the motion.
    func showCalendar() {
        calendarHeldKeys.removeAll()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // The panel's silhouette to grow from, captured before the fade so a
        // mid-animation size change can't move the calendar's start.
        let morphSize: CGSize? = notchWindow?.isVisible == true && !reduceMotion
            ? notchWindow?.frame.size
            : nil
        if notchWindow?.isVisible == true {
            if reduceMotion {
                closeNotchPanel(animated: false)
            } else {
                fadeOutNotchPanelForCalendar()
            }
        } else if popover.isShown {
            closePopover()
        }
        reviewNudgeController?.dismiss()

        calendarCloseGeneration &+= 1
        let generation = calendarCloseGeneration
        calendarReveal.reset()
        calendarReveal.startSize = morphSize

        prepareCalendarContent()
        guard let window = calendarWindow else { return }
        window.alphaValue = 1
        window.ignoresMouseEvents = false
        positionNotchWindow(window)
        applyAppearance(SettingsStore.shared.appearance)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        if reduceMotion {
            calendarReveal.open(animated: false)
            store.refresh()
        } else {
            provideNotchHaptic()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.calendarWindow?.isVisible == true,
                      self.calendarCloseGeneration == generation else { return }
                self.calendarReveal.open(animated: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + self.calendarReveal.duration + self.calendarReveal.contentFadeDuration) { [weak self] in
                    guard let self, self.calendarWindow?.isVisible == true,
                          self.calendarCloseGeneration == generation else { return }
                    self.store.refresh()
                }
            }
        }
    }

    private func closeCalendar(animated: Bool = true) {
        calendarHeldKeys.removeAll()
        guard let window = calendarWindow, window.isVisible else { return }
        calendarCloseGeneration &+= 1
        let generation = calendarCloseGeneration
        window.ignoresMouseEvents = true
        if !animated || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            window.orderOut(nil)
            calendarReveal.reset()
            return
        }
        calendarReveal.retract()
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchRevealController.closingDuration) { [weak self, weak window] in
            guard let self, let window,
                  self.calendarCloseGeneration == generation else { return }
            window.orderOut(nil)
            self.calendarReveal.reset()
        }
    }

    /// Returns from the calendar to the reminders panel by shrinking the
    /// calendar into the panel's silhouette and revealing the panel in place —
    /// the shortcut's open morph played backwards, so the shape reads as one
    /// form changing into the other rather than a close followed by an open.
    /// Falls back to that plain handoff when there is no panel silhouette to
    /// land in (anchored popover, Reduced Motion, no panel window).
    func returnToMainFromCalendar() {
        guard SettingsStore.shared.notchPopover,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let calendar = calendarWindow, calendar.isVisible else {
            showMainReminders()
            return
        }
        prepareNotchContent()
        guard let panel = notchWindow else {
            showMainReminders()
            return
        }
        calendarHeldKeys.removeAll()
        reviewNudgeController?.didReview()

        // Park the panel at its full size, invisible and above the calendar,
        // so the shrink has a silhouette to land in. Its own reveal is already
        // complete, so nothing grows a second time; only the window fades in,
        // and only once the calendar has reached it.
        let panelSize = NSSize(width: SettingsStore.shared.notchPanelWidth,
                               height: MainPopoverLayout.height(pomodoroEnabled: SettingsStore.shared.pomodoroEnabled) + notchTopInset)
        notchCloseGeneration &+= 1
        let panelGeneration = notchCloseGeneration
        notchReveal.reset()
        panel.setContentSize(panelSize)
        positionNotchWindow(panel)
        applyAppearance(SettingsStore.shared.appearance)
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFront(nil)
        // Paint the panel's full size while it is still invisible, so the
        // first paint can't land on top of the shrink's first frames and make
        // it jump.
        panel.layoutIfNeeded()
        panel.displayIfNeeded()
        notchReveal.open(animated: false)

        // Shrink the calendar into that silhouette, then hand over while the
        // two glass shapes are identical, so the swap itself is invisible.
        calendarCloseGeneration &+= 1
        let calendarGeneration = calendarCloseGeneration
        calendar.ignoresMouseEvents = true
        calendarReveal.retract(into: panelSize)

        DispatchQueue.main.asyncAfter(deadline: .now() + calendarReveal.duration) { [weak self, weak panel, weak calendar] in
            guard let self, let panel, let calendar,
                  self.notchCloseGeneration == panelGeneration,
                  self.calendarCloseGeneration == calendarGeneration,
                  panel.isVisible else {
                self?.abandonCalendarReturn()
                return
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.08
                context.allowsImplicitAnimation = true
                panel.animator().alphaValue = 1
            } completionHandler: { [weak self, weak panel, weak calendar] in
                MainActor.assumeIsolated {
                    guard let self, let panel, let calendar,
                          self.notchCloseGeneration == panelGeneration,
                          self.calendarCloseGeneration == calendarGeneration else {
                        self?.abandonCalendarReturn()
                        return
                    }
                    calendar.orderOut(nil)
                    self.calendarReveal.reset()
                    panel.ignoresMouseEvents = false
                    panel.makeKey()
                    self.store.refresh()
                }
            }
        }
    }

    /// Drops the invisible panel a cancelled calendar→panel morph left ordered
    /// front, so a later open isn't left click-through behind nothing.
    private func abandonCalendarReturn() {
        guard let panel = notchWindow, panel.alphaValue == 0 else { return }
        panel.orderOut(nil)
        panel.alphaValue = 1
        panel.ignoresMouseEvents = false
    }


    @objc private func refreshData() {
        store.refresh()
    }

    // `.transient` used to close on deactivation; keep that behavior explicit.
    func applicationDidResignActive(_ notification: Notification) {
        // The notch panel stays put when the app loses focus (e.g. ⌘-Tab): it
        // is dismissed only by clicking off it or by the toggle shortcut. The
        // menu-bar popover keeps its original deactivate-to-close behaviour.
        if popover.isShown { closePopover() }
        if quickAddWindow?.isVisible == true { closeQuickAdd() }
        if calendarWindow?.isVisible == true { closeCalendar() }
    }

    // MARK: - Service window

    /// Brings up (or reuses) the "New Reminders" window with a bulk preview.
    func showBulkPreview(text: String, allowLocationLookup: Bool = true) {
        let preview = BulkReminderPreview(text: text,
                                           allowLocationLookup: allowLocationLookup,
                                           onCancel: { self.serviceWindow?.close() },
                                           onDone: { self.serviceWindow?.close() })
        let rootView = AnyView(
            preview
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
