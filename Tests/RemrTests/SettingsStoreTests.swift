import AppKit
import SwiftUI
import XCTest
@testable import remr

@MainActor
final class SettingsStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "remr.test.appearance.\(UUID().uuidString)")!
    }

    func testDefaultsToFollowSystem() {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.appearance, .system)
        XCTAssertNil(store.appearance.colorScheme)
    }

    func testAppearancePersistsAcrossInstances() {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults)

        store.setAppearance(.dark)

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.appearance, .dark)
        XCTAssertEqual(reloaded.appearance.colorScheme, .dark)
    }

    func testInvalidPersistedAppearanceFallsBackToFollowSystem() {
        let defaults = makeDefaults()
        defaults.set("sepia", forKey: "remr.appearance")

        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.appearance, .system)
    }

    func testMenuBarIconDefaultsToBellBadgeAccent() {
        let store = SettingsStore(defaults: makeDefaults())

        XCTAssertEqual(store.menuBarIconSymbol, .bellBadge)
        XCTAssertEqual(store.menuBarIconStyle, .accent)
    }

    func testMenuBarIconPersistsAcrossInstances() {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults)

        store.setMenuBarIconSymbol(.moon)
        store.setMenuBarIconStyle(.custom)
        // A concrete component color, as a ColorPicker produces (SwiftUI
        // static colors like .red bridge to appearance-adaptive catalog
        // colors, which would resolve to non-primary components).
        store.setMenuBarIconColor(Color(NSColor(srgbRed: 0.9, green: 0.2, blue: 0.4, alpha: 1)))

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.menuBarIconSymbol, .moon)
        XCTAssertEqual(reloaded.menuBarIconStyle, .custom)
        // Canonical storage means the reloaded color is exactly the value the
        // picker set — the representation-stable contract behind the picker
        // staying in sync across restarts.
        XCTAssertEqual(reloaded.menuBarIconColor, Color(red: 0.9, green: 0.2, blue: 0.4, opacity: 1))
    }

    func testMenuBarIconColorMigratesFromLegacyArchive() {
        let defaults = makeDefaults()
        let data = try! NSKeyedArchiver.archivedData(withRootObject: NSColor(srgbRed: 0.5, green: 0.6, blue: 0.7, alpha: 1),
                                                     requiringSecureCoding: true)
        defaults.set(data, forKey: "remr.menuBarIconColor")

        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.menuBarIconColor, Color(red: 0.5, green: 0.6, blue: 0.7, opacity: 1))
        // The legacy value is rewritten in the canonical form.
        XCTAssertEqual(defaults.array(forKey: "remr.menuBarIconColorRGBA") as? [Double],
                       [0.5, 0.6, 0.7, 1.0])
    }

    func testInvalidPersistedMenuBarIconColorFallsBackToAccent() {
        let defaults = makeDefaults()
        defaults.set([0.9, 0.2], forKey: "remr.menuBarIconColorRGBA")

        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.menuBarIconColor, .accentColor)
    }

    func testInvalidPersistedMenuBarIconFallsBackToDefaults() {
        let defaults = makeDefaults()
        defaults.set("warpdrive", forKey: "remr.menuBarIconSymbol")
        defaults.set("neon", forKey: "remr.menuBarIconStyle")

        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.menuBarIconSymbol, .bellBadge)
        XCTAssertEqual(store.menuBarIconStyle, .accent)
    }

    func testMenuBarIconStyleMigratesLegacyNames() {
        // A store that persisted the pre-rename raw values.
        let defaults = makeDefaults()
        defaults.set("template", forKey: "remr.menuBarIconStyle")
        XCTAssertEqual(SettingsStore(defaults: defaults).menuBarIconStyle, .automatic)

        let monochromeDefaults = makeDefaults()
        monochromeDefaults.set("monochrome", forKey: "remr.menuBarIconStyle")
        XCTAssertEqual(SettingsStore(defaults: monochromeDefaults).menuBarIconStyle, .accent)
    }
}
