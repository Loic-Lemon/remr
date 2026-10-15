import AppKit
import Combine
import CoreGraphics
import SwiftUI

/// A nudge is visible without activating remr or taking keyboard focus.
private final class ReviewNudgePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

private final class ReviewNudgeHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class ReviewNudgeController {
    private struct Configuration: Equatable {
        let enabled: Bool
        let minimum: Double
        let maximum: Double
    }

    private enum SuspensionReason { case sleep, display, session }

    private let store: ReminderStore
    private let settings: SettingsStore
    private let defaults: UserDefaults
    private let isBusy: () -> Bool
    private let onReview: () -> Void
    private let scheduleKey = "remr.reviewNudgeNextDate"
    private var configuration: Configuration?
    private var schedule: ReviewNudgeSchedule
    private var timer: Timer?
    private var window: ReviewNudgePanel?
    private var presentation: ReviewNudgePresentation?
    private var generation = 0
    private var suspensionReasons: Set<SuspensionReason> = []
    private var resumeNotBefore = Date.distantPast
    private var settingsSubscription: AnyCancellable?
    private var workspaceObservers: [NSObjectProtocol] = []

    init(store: ReminderStore, settings: SettingsStore,
         defaults: UserDefaults = .standard,
         isBusy: @escaping () -> Bool, onReview: @escaping () -> Void) {
        self.store = store
        self.settings = settings
        self.defaults = defaults
        self.isBusy = isBusy
        self.onReview = onReview
        schedule = ReviewNudgeSchedule(nextDueAt: defaults.object(forKey: "remr.reviewNudgeNextDate") as? Date)

        settingsSubscription = settings.$reviewNudgesEnabled
            .combineLatest(settings.$reviewNudgeMinimumMinutes, settings.$reviewNudgeMaximumMinutes)
            .sink { [weak self] enabled, minimum, maximum in
                self?.configure(Configuration(enabled: enabled, minimum: minimum, maximum: maximum))
            }

        let workspace = NSWorkspace.shared.notificationCenter
        let suspensionNotifications: [(Notification.Name, SuspensionReason)] = [
            (NSWorkspace.willSleepNotification, .sleep),
            (NSWorkspace.screensDidSleepNotification, .display),
            (NSWorkspace.sessionDidResignActiveNotification, .session)
        ]
        for (name, reason) in suspensionNotifications {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.suspensionReasons.insert(reason)
                    self?.dismiss()
                }
            })
        }
        let resumeNotifications: [(Notification.Name, SuspensionReason)] = [
            (NSWorkspace.didWakeNotification, .sleep),
            (NSWorkspace.screensDidWakeNotification, .display),
            (NSWorkspace.sessionDidBecomeActiveNotification, .session)
        ]
        for (name, reason) in resumeNotifications {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.suspensionReasons.remove(reason)
                    self?.resumeNotBefore = Date().addingTimeInterval(60)
                }
            })
        }
        workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                        object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        })
    }

    deinit {
        timer?.invalidate()
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    /// Main-panel reviews restart the interval. Quick Add does not call this.
    func didReview() {
        dismiss()
        if configuration?.enabled == true { scheduleNext(after: Date()) }
    }

    func preview() { present() }

    func dismiss(animated: Bool = false) {
        generation &+= 1
        guard let panel = window else { return }
        let presentation = presentation
        window = nil
        self.presentation = nil
        panel.ignoresMouseEvents = true
        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            withAnimation(.easeInOut(duration: 0.18)) {
                presentation?.expanded = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                panel.orderOut(nil)
            }
        } else {
            panel.orderOut(nil)
        }
    }

    private func configure(_ newValue: Configuration) {
        guard configuration != newValue else { return }
        let firstConfiguration = configuration == nil
        configuration = newValue
        timer?.invalidate()
        timer = nil
        if !newValue.enabled {
            dismiss()
            schedule.clear()
            defaults.removeObject(forKey: scheduleKey)
            return
        }
        if !firstConfiguration || schedule.nextDueAt == nil { scheduleNext(after: Date()) }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func scheduleNext(after date: Date) {
        guard let configuration else { return }
        schedule.schedule(after: date, minimumMinutes: configuration.minimum,
                          maximumMinutes: configuration.maximum, sample: Double.random(in: 0...1))
        defaults.set(schedule.nextDueAt, forKey: scheduleKey)
    }

    private func tick() {
        let now = Date()
        guard configuration?.enabled == true, schedule.isDue(at: now), now >= resumeNotBefore,
              suspensionReasons.isEmpty, window == nil, !isBusy(),
              CGEventSource.secondsSinceLastEventType(
                .combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!) < 300,
              store.accessState == .authorized else { return }
        let hasTasks = store.allReminders.contains {
            !$0.isCompleted && !settings.hiddenLists.contains($0.calendar?.calendarIdentifier ?? "")
        }
        guard hasTasks else { return }
        guard present() else { return }
        scheduleNext(after: now)
    }

    @discardableResult
    private func present() -> Bool {
        guard suspensionReasons.isEmpty,
              let screen = NSScreen.screens.first(where: { $0.frame.origin == .zero })
                ?? NSScreen.main ?? NSScreen.screens.first else { return false }
        dismiss()
        let menuBar = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        let notchHeight = screen.auxiliaryTopLeftArea.map { max(0, screen.frame.maxY - $0.minY) } ?? 0
        let height = max(24, menuBar, notchHeight, screen.safeAreaInsets.top)
        let housingWidth = screen.auxiliaryTopLeftArea.flatMap { left in
            screen.auxiliaryTopRightArea.map { max(0, $0.minX - left.maxX) }
        } ?? 180
        let centreX = screen.auxiliaryTopLeftArea.flatMap { left in
            screen.auxiliaryTopRightArea.map { (left.maxX + $0.minX) / 2 }
        } ?? screen.frame.midX
        let wingWidth: CGFloat = 156
        let width = housingWidth + wingWidth * 2
        let presentation = ReviewNudgePresentation()
        self.presentation = presentation
        let root = ReviewNudgeView(housingWidth: housingWidth, wingWidth: wingWidth, height: height,
                                  presentation: presentation,
                                  onReview: { [weak self] in
                                      guard let self else { return }
                                      self.onReview()
                                  }, onDismiss: { [weak self] in self?.dismiss(animated: true) })
        let hosting = ReviewNudgeHostingView(rootView: AnyView(root))
        hosting.sizingOptions = []
        let panel = ReviewNudgePanel(contentRect: NSRect(x: 0, y: 0, width: width,
                                                        height: height),
                                     styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.setFrameOrigin(NSPoint(x: centreX - width / 2,
                                     y: screen.frame.maxY - panel.frame.height))
        window = panel
        panel.orderFrontRegardless()
        let currentGeneration = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 18) { [weak self] in
            guard let self, self.generation == currentGeneration else { return }
            self.dismiss(animated: true)
        }
        return true
    }
}
