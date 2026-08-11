import XCTest
@testable import remr

@MainActor
final class FilterStoreTests: XCTestCase {

    /// A fresh, unique UserDefaults suite per test, so no test can pollute another.
    private func makeStore() -> (FilterStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "remr.test.\(UUID().uuidString)")!
        return (FilterStore(defaults: defaults), defaults)
    }

    func testStartsUnfiltered() {
        let (store, _) = makeStore()
        XCTAssertNil(store.tag)
    }

    func testToggleSetsNormalizedTag() {
        let (store, _) = makeStore()
        store.toggle("Groceries")
        XCTAssertEqual(store.tag, "groceries")
    }

    func testToggleActiveChipClears() {
        let (store, _) = makeStore()
        store.toggle("urgent")
        store.toggle("URGENT")   // same tag, different case → clears
        XCTAssertNil(store.tag)
    }

    func testToggleSwitchesTags() {
        let (store, _) = makeStore()
        store.toggle("home")
        store.toggle("work")
        XCTAssertEqual(store.tag, "work")
    }

    func testClear() {
        let (store, _) = makeStore()
        store.toggle("home")
        store.clear()
        XCTAssertNil(store.tag)
    }

    func testPersistsAcrossInstances() {
        let defaults = UserDefaults(suiteName: "remr.test.\(UUID().uuidString)")!
        FilterStore(defaults: defaults).toggle("urgent")
        let reloaded = FilterStore(defaults: defaults)
        XCTAssertEqual(reloaded.tag, "urgent")
    }

    func testEmptySavedValueIsIgnored() {
        let defaults = UserDefaults(suiteName: "remr.test.\(UUID().uuidString)")!
        defaults.set("", forKey: "remr.tagFilter")
        let store = FilterStore(defaults: defaults)
        XCTAssertNil(store.tag)
    }
}
