import XCTest
@testable import remr

final class FeatureInventoryTests: XCTestCase {
    func testFeatureInventoryRowsHaveUniqueNamesAndSummaries() {
        let rows = FeatureInventory.all
        let ids = Set(rows.map(\.id))

        XCTAssertFalse(rows.isEmpty)
        XCTAssertEqual(ids.count, rows.count)
        XCTAssertTrue(rows.allSatisfy { !$0.name.isEmpty && !$0.summary.isEmpty })
    }

    func testInventorySeparatesShippedFeaturesAndIdeas() {
        XCTAssertGreaterThan(FeatureInventory.implementedCount, 0)
        XCTAssertGreaterThan(FeatureInventory.ideaCount, 0)
        XCTAssertLessThan(FeatureInventory.implementedCount, FeatureInventory.all.count)
    }
}
