import XCTest
@testable import EQCore

final class FeatureFrameworkTests: XCTestCase {
    func testOldSettingsWithoutFeaturesDecode() throws {
        let json = #"{"enabled":true,"bandGains":[0,0,0,0,0,0,0,0,0,0]}"#
        let s = try JSONDecoder().decode(EQSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.features, FeatureSettings())
    }

    func testFeaturesRoundTrip() throws {
        let s = EQSettings()
        let back = try JSONDecoder().decode(EQSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
    }

    func testCatalogueIdsAreUniqueAndToggleable() {
        let ids = FeatureSettings.catalogue.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        for id in ids {
            var f = FeatureSettings()
            f[isOn: id] = true
            XCTAssertTrue(f[isOn: id], "\(id) should toggle on")
            f[isOn: id] = false
            XCTAssertFalse(f[isOn: id], "\(id) should toggle off")
        }
    }
}
