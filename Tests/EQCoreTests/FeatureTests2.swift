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

final class MeasuredProfileTests: XCTestCase {
    func testEveryModelHasMeasuredData() {
        let models = HeadphoneProfile.builtIn.filter { $0.provenance.kind == .approximation }
        XCTAssertFalse(models.isEmpty)
        for p in models {
            XCTAssertNotNil(HeadphoneProfile.measurements[p.id], "\(p.name) has no measurement")
        }
    }

    func testMeasuredSwapKeepsIdsAndChangesSource() {
        let measured = HeadphoneProfile.builtIn(measured: true)
        XCTAssertEqual(measured.map(\.id), HeadphoneProfile.builtIn.map(\.id))
        let xm5 = measured.first { $0.id == "sony-xm5" }!
        XCTAssertEqual(xm5.provenance.kind, .measured)
        XCTAssertEqual(xm5.provenance.measuredBy, "oratory1990")
        XCTAssertTrue(xm5.provenance.url!.contains("Sony%20WH-1000XM5"))
        XCTAssertLessThanOrEqual(xm5.filters.count, HeadphoneProfile.maxFilters)
        // Generic profiles stay generic.
        XCTAssertEqual(measured.first { $0.id == "generic-over" }!.provenance.kind, .generic)
        // Off → approximations.
        XCTAssertEqual(HeadphoneProfile.builtIn(measured: false).first { $0.id == "sony-xm5" }!.provenance.kind, .approximation)
    }

    func testMeasuredCurvesAreSane() {
        for (id, m) in HeadphoneProfile.measurements {
            let peak = FrequencyResponse.peakGain(filters: m.filters)
            XCTAssertLessThan(peak, 20, "\(id) boosts implausibly")
            XCTAssertTrue(m.filters.allSatisfy { $0.frequency >= 10 && $0.frequency <= 20_000 && $0.q > 0 })
        }
    }
}
