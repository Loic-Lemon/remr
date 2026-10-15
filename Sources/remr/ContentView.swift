import SwiftUI

/// Which window chrome the main content is presented in. The native popover
/// supplies its own Liquid Glass surface, while the notch panel is a
/// borderless window that has to paint its own glass.
enum MainSurfaceStyle {
    case popover
    case floatingPanel
}

struct ContentView: View {
    var surface: MainSurfaceStyle = .popover
    /// Content width. The menu-bar popover is fixed at 400; the notch panel
    /// uses the user's configured width.
    var width: CGFloat = 400
    /// Empty glass added above the content in the notch panel, so the surface
    /// reaches up to the screen edge behind the menu bar and notch while the
    /// content itself still starts below them.
    var topInset: CGFloat = 0
    /// Side inset for the notch panel, keeping the content clear of the
    /// silhouette's shoulders.
    var horizontalInset: CGFloat = 0
    var notchReveal: NotchRevealController? = nil
    var notchCollapsedWidth: CGFloat = 172

    @EnvironmentObject var store: ReminderStore
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        Group {
            switch store.accessState {
            case .notDetermined:
                permissionView
            case .denied:
                deniedView
            case .authorized:
                MainView(surface: surface)
            }
        }
        .frame(width: width)
        .frame(minHeight: 600)
        .onAppear {
            PomodoroKeyProbe.log("ContentView.onAppear accessState=\(store.accessState)")
        }
        .notchContentReveal(notchReveal)
        .padding(.top, topInset)
        .padding(.horizontal, horizontalInset)
        .remrMainSurface(surface, notchHeadHeight: topInset,
                         notchReveal: notchReveal, notchCollapsedWidth: notchCollapsedWidth)
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
            .liquidGlassButtonStyle(.bordered, prominent: true)
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
            .liquidGlassButtonStyle(.bordered)
            Button("Try Again") {
                Task { await store.requestAccess() }
            }
            .liquidGlassButtonStyle(.bordered)
        }
        .padding(24)
    }
}
