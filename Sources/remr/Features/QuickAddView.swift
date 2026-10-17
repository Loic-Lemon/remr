import AppKit
import SwiftUI

/// A compact, standalone reminder composer used by the global quick-add
/// shortcut. The editor remains the single source of truth for parsing and
/// EventKit creation; this view only supplies transient popup chrome.
struct QuickAddView: View {
    @EnvironmentObject private var store: ReminderStore
    @EnvironmentObject private var settings: SettingsStore

    /// Shared with the AppKit panel so the glass fills the entire window.
    static let width: CGFloat = 560

    /// A new identity resets text, focus, and parse preview on every opening.
    let sessionID: UUID
    let onHeightChange: (CGFloat) -> Void
    let initialText: String
    let onCancel: () -> Void
    let onCreated: () -> Void

    init(sessionID: UUID,
         initialText: String = "",
         onCancel: @escaping () -> Void,
         onCreated: @escaping () -> Void,
         onHeightChange: @escaping (CGFloat) -> Void = { _ in }) {
        self.sessionID = sessionID
        self.onHeightChange = onHeightChange
        self.initialText = initialText
        self.onCancel = onCancel
        self.onCreated = onCreated
    }

    var body: some View {
        QuickAddSurface(onHeightChange: onHeightChange) {
            content
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick add reminder")
        .onExitCommand(perform: onCancel)
    }

    @ViewBuilder
    private var content: some View {
        switch store.accessState {
        case .authorized:
            // Use the same focused input surface as the main notch panel.
            NewReminderView(initialText: initialText, onEscape: onCancel, onCreated: onCreated)
                .id(sessionID)
                .environmentObject(store)
                .environmentObject(settings)
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

/// The popup has no spare vertical space: its window follows this padded
/// content's height, including the composer's animated expansion.
struct QuickAddSurface<Content: View>: View {
    let onHeightChange: (CGFloat) -> Void
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(12)
            .frame(width: QuickAddView.width)
            .fixedSize(horizontal: false, vertical: true)
            .liquidGlassPopup(frosted: true)
            .background(HeightReader(onChange: onHeightChange))
    }
}
