import AppKit
import SwiftUI

/// A compact, standalone reminder composer used by the global quick-add
/// shortcut. The editor remains the single source of truth for parsing and
/// EventKit creation; this view only supplies transient popup chrome.
struct QuickAddView: View {
    @EnvironmentObject private var store: ReminderStore
    @EnvironmentObject private var settings: SettingsStore

    /// A new identity is supplied for every popup presentation so the editor's
    /// text, focus, and parse preview never leak between sessions.
    let sessionID: UUID
    let onCancel: () -> Void
    let onCreated: () -> Void
    let onHeightChange: ((CGFloat) -> Void)?

    init(sessionID: UUID,
         onCancel: @escaping () -> Void,
         onCreated: @escaping () -> Void,
         onHeightChange: ((CGFloat) -> Void)? = nil) {
        self.sessionID = sessionID
        self.onCancel = onCancel
        self.onCreated = onCreated
        self.onHeightChange = onHeightChange
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .opacity(0.45)
            content
        }
        .frame(width: 440)
        .background(QuickAddHeightReporter(onHeightChange: onHeightChange)
            .allowsHitTesting(false))
        .liquidGlassPopup()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick add reminder")
        .onExitCommand(perform: onCancel)
    }
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppPalette.popupAccent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Quick add reminder")
                    .font(.headline)
                Text("Return saves · Esc dismisses")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch store.accessState {
        case .authorized:
            NewReminderView(onEscape: onCancel, onCreated: onCreated)
                .id(sessionID)
                .environmentObject(store)
                .environmentObject(settings)
                .padding(.bottom, 2)
        case .notDetermined:
            permissionView(
                icon: "checklist",
                title: "Allow Reminders access",
                message: "remr needs access to create reminders from this shortcut.",
                primaryTitle: "Allow access to Reminders",
                primaryAction: { Task { await store.requestAccess() } },
                showsSettings: false
            )
        case .denied:
            permissionView(
                icon: "exclamationmark.triangle",
                title: "Reminders access is off",
                message: "Enable Reminders access in System Settings to use quick add.",
                primaryTitle: "Open System Settings",
                primaryAction: openRemindersSettings,
                showsSettings: true
            )
        }
    }

    private func permissionView(icon: String,
                                title: String,
                                message: String,
                                primaryTitle: String,
                                primaryAction: @escaping () -> Void,
                                showsSettings: Bool) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(icon == "exclamationmark.triangle" ? Color.orange : Color.accentColor)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            HStack(spacing: 8) {
                Button(primaryTitle, action: primaryAction)
                    .keyboardShortcut(.defaultAction)
                    .liquidGlassButtonStyle(.bordered, prominent: true)
                    .accessibilityLabel(primaryTitle)
                if showsSettings {
                    Button("Try again") {
                        Task { await store.requestAccess() }
                    }
                    .liquidGlassButtonStyle(.bordered)
                    .accessibilityLabel("Try again")
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
    }

    private func openRemindersSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") else { return }
        NSWorkspace.shared.open(url)
    }
}


private struct QuickAddHeightReporter: NSViewRepresentable {
    let onHeightChange: ((CGFloat) -> Void)?

    func makeNSView(context: Context) -> HeightReportingView {
        HeightReportingView(onHeightChange: onHeightChange)
    }

    func updateNSView(_ nsView: HeightReportingView, context: Context) {
        nsView.onHeightChange = onHeightChange
        nsView.scheduleMeasurement()
    }
}

private final class HeightReportingView: NSView {
    var onHeightChange: ((CGFloat) -> Void)?

    private var measurementGeneration = 0
    private var measurementPending = false
    private var lastReportedHeight: CGFloat?

    init(onHeightChange: ((CGFloat) -> Void)?) {
        self.onHeightChange = onHeightChange
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleMeasurement()
    }

    override func layout() {
        super.layout()
        scheduleMeasurement()
    }

    func scheduleMeasurement() {
        measurementGeneration &+= 1
        guard !measurementPending else { return }
        measurementPending = true
        let generation = measurementGeneration

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.measurementPending = false
            guard generation == self.measurementGeneration else {
                self.scheduleMeasurement()
                return
            }
            self.measureAndReport()
        }
    }

    private func measureAndReport() {
        guard let contentView = window?.contentView else { return }
        contentView.layoutSubtreeIfNeeded()

        let fittingHeight = contentView.fittingSize.height
        let intrinsicHeight = contentView.intrinsicContentSize.height
        let currentHeight = contentView.bounds.height
        let fittingIsValid = fittingHeight.isFinite && fittingHeight > 0
        let intrinsicIsValid = intrinsicHeight.isFinite && intrinsicHeight > 0

        let height: CGFloat?
        if fittingIsValid && intrinsicIsValid {
            // A hosting view can temporarily expose its fixed window frame as
            // fittingSize while its intrinsic size already reflects new content.
            let fittingIsCurrent = abs(fittingHeight - currentHeight) < 0.5
            let intrinsicIsCurrent = abs(intrinsicHeight - currentHeight) < 0.5
            height = fittingIsCurrent && !intrinsicIsCurrent ? intrinsicHeight : fittingHeight
        } else if fittingIsValid {
            height = fittingHeight
        } else if intrinsicIsValid {
            height = intrinsicHeight
        } else {
            height = nil
        }

        guard let height,
              lastReportedHeight.map({ abs($0 - height) >= 0.5 }) ?? true else { return }
        lastReportedHeight = height
        onHeightChange?(height)
    }
}