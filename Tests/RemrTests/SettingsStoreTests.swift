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
}
