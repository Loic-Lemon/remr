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

    init(sessionID: UUID,
         onCancel: @escaping () -> Void,
         onCreated: @escaping () -> Void) {
        self.sessionID = sessionID
        self.onCancel = onCancel
        self.onCreated = onCreated
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .opacity(0.45)
            content
        }
        .frame(width: 440)
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
            // The editor sits directly on the panel's glass (no inner glass
            // surface), so the liquid-glass look stays constant as the
            // description expands; the unfold is pure SwiftUI inside the
            // fixed-size panel.
            NewReminderView(onEscape: onCancel, onCreated: onCreated, hasOwnGlass: false)
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