import AppKit
import SwiftUI

@main
struct RemrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { StandaloneSettingsRoot() }
    }
}

private struct StandaloneSettingsRoot: View {
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        SettingsView()
            .environmentObject(settings)
            .remrAppearance(using: settings)
            .background(SettingsWindowAppearanceBridge(mode: settings.appearance))
    }
}

private struct SettingsWindowAppearanceBridge: NSViewRepresentable {
    let mode: AppearanceMode

    func makeNSView(context: Context) -> AppearanceView {
        AppearanceView(mode: mode)
    }

    func updateNSView(_ nsView: AppearanceView, context: Context) {
        nsView.mode = mode
        nsView.applyAppearance()
    }

    final class AppearanceView: NSView {
        var mode: AppearanceMode

        init(mode: AppearanceMode) {
            self.mode = mode
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyAppearance()
        }

        func applyAppearance() {
            window?.appearance = mode.nsAppearance
        }
    }
}
