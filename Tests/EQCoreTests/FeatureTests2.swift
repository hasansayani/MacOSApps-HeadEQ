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

final class DeviceMemoryTests: XCTestCase {
    func testSwitchingSavesAndRestores() {
        var mem = DeviceMemory()
        var headphones = EQSettings()
        headphones.headphoneProfileID = "sony-xm3"
        headphones.bandGains = [3, 2, 1, 0, 0, 0, 0, 0, 1, 2]
        headphones.output.crossfeed = 0.4

        // Switch from headphones to an unknown DAC: settings carry over unchanged.
        let onDAC = mem.switching(from: ("hp-uid", "WH-1000XM3"), to: "dac-uid", current: headphones)
        XCTAssertEqual(onDAC, headphones)

        // Tweak the DAC, switch back: the headphones' own settings return.
        var dacSettings = onDAC
        dacSettings.headphoneProfileID = "hd600"
        dacSettings.bandGains = Array(repeating: 0, count: 10)
        dacSettings.output.crossfeed = 0
        let back = mem.switching(from: ("dac-uid", "USB DAC"), to: "hp-uid", current: dacSettings)
        XCTAssertEqual(back.headphoneProfileID, "sony-xm3")
        XCTAssertEqual(back.bandGains, headphones.bandGains)
        XCTAssertEqual(back.output.crossfeed, 0.4)

        // And the DAC was remembered.
        XCTAssertEqual(mem.snapshot(for: "dac-uid")?.headphoneProfileID, "hd600")
        XCTAssertEqual(mem.snapshot(for: "dac-uid")?.deviceName, "USB DAC")
    }

    func testGlobalOptionsAreNotOverwritten() {
        var mem = DeviceMemory()
        var a = EQSettings(); a.hearing.maxLevelSPL = 80; a.enabled = true
        mem.remember(a, deviceUID: "x", deviceName: "X")
        var current = EQSettings(); current.hearing.maxLevelSPL = 95; current.enabled = false
        let restored = mem.snapshot(for: "x")!.applied(to: current)
        XCTAssertEqual(restored.hearing.maxLevelSPL, 95)
        XCTAssertFalse(restored.enabled)
    }

    func testForgetAndCodable() throws {
        var mem = DeviceMemory()
        mem.remember(EQSettings(), deviceUID: "a", deviceName: "A")
        let back = try JSONDecoder().decode(DeviceMemory.self, from: JSONEncoder().encode(mem))
        XCTAssertEqual(back, mem)
        mem.forget("a")
        XCTAssertNil(mem.snapshot(for: "a"))
    }
}

final class ThemeTests: XCTestCase {
    func testPaletteIdsUniqueAndColorsValid() {
        let ids = ThemePalette.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        for p in ThemePalette.all {
            for hex in [p.accent] + p.gradient + (p.background ?? []) {
                XCTAssertTrue(hex.hasPrefix("#") && hex.count == 7 && UInt64(hex.dropFirst(), radix: 16) != nil, "\(p.id): \(hex)")
            }
            XCTAssertGreaterThanOrEqual(p.gradient.count, 2, p.id)
        }
    }

    func testPlayerSkinsAreDarkRetroAndGrouped() {
        let skins = ThemePalette.all.filter { $0.group == "Player skins" }
        XCTAssertEqual(skins.count, 5)
        XCTAssertTrue(skins.allSatisfy { $0.retro && $0.isDark })
        XCTAssertEqual(ThemePalette.groups, ["HeadEQ", "Player skins"])
        // Classic base runs green (quiet) → red (loud), like the original spectrum analyser.
        let classic = ThemePalette.named("skin-classic")
        XCTAssertEqual(classic.gradient.first, "#18B818")
        XCTAssertEqual(classic.gradient.last, "#E01010")
    }
}
