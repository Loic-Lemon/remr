import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: ReminderStore

    var body: some View {
        Group {
            switch store.accessState {
            case .notDetermined:
                permissionView
            case .denied:
                deniedView
            case .authorized:
                MainView()
            }
        }
        .preferredColorScheme(.light)
        .frame(width: 400, height: 600)
        .background(.ultraThinMaterial.opacity(0.45))
    }

    // MARK: - Not determined

    private var permissionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text("remr needs access to your Reminders to show, create, and manage them.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 260)
            Button("Allow access to Reminders") {
                Task { await store.requestAccess() }
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(24)
    }

    // MARK: - Denied

    private var deniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("Reminders access was denied. Enable it in System Settings to use remr.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 260)
            Button("Open System Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!)
            }
            Button("Try Again") {
                Task { await store.requestAccess() }
            }
        }
        .padding(24)
    }
}
