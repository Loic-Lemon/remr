import SwiftUI

@main
struct RemrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { SettingsView().environmentObject(SettingsStore.shared) }
    }
}
