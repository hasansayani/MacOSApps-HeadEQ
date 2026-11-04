import XCTest
@testable import EQCore

final class DACTests: XCTestCase {
    private var neutral: EQSettings {
        var s = EQSettings()
        s.hearing.enabled = false
        s.features.dac.enabled = true
        return s
    }

    func testDefaultFlatChainIsNeutralWithoutHearingProtection() {
        XCTAssertEqual(neutral.nonNeutralReasons(headphone: .none), [])
        XCTAssertTrue(neutral.shouldBypass(headphone: .none))
    }

    func testEachChangeBreaksNeutrality() {
        let mods: [(String, (inout EQSettings) -> Void)] = [
            ("Graphic EQ", { $0.bandGains[3] = 2 }),
            ("Output gain", { $0.output.gainDB = -1 }),
            ("Balance", { $0.output.balance = 0.2 }),
            ("Stereo width", { $0.output.mono = true }),
            ("Crossfeed", { $0.output.crossfeed = 0.3 }),
            ("Hearing protection", { $0.hearing.enabled = true }),
            ("Virtual surround", { $0.features.surround.enabled = true }),
            ("Volume levelling", { $0.features.leveler.enabled = true }),
        ]
        for (name, mod) in mods {
            var s = neutral
            mod(&s)
            XCTAssertFalse(s.isNeutral(headphone: .none), name)
            XCTAssertFalse(s.shouldBypass(headphone: .none), name)
        }
        let xm3 = HeadphoneProfile.builtIn.first { $0.id == "sony-xm3" }!
        XCTAssertFalse(neutral.isNeutral(headphone: xm3))
    }

    func testBypassRequiresDACModeAndOption() {
        var s = neutral
        s.features.dac.enabled = false
        XCTAssertFalse(s.shouldBypass(headphone: .none))
        s.features.dac.enabled = true
        s.features.dac.bypassWhenNeutral = false
        XCTAssertFalse(s.shouldBypass(headphone: .none))
    }

    func testPhysicalFormatDescription() {
        XCTAssertEqual(PhysicalFormat(sampleRate: 96_000, bitsPerChannel: 24, channels: 2, isFloat: false).description, "24-bit · 96 kHz · 2 ch")
        XCTAssertEqual(PhysicalFormat(sampleRate: 44_100, bitsPerChannel: 32, channels: 2, isFloat: true).description, "32-bit float · 44.1 kHz · 2 ch")
    }

    func testPreferredRatesPersist() throws {
        var s = DACSettings(); s.preferredRates["dac-1"] = 96_000
        let back = try JSONDecoder().decode(DACSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.preferredRates["dac-1"], 96_000)
    }
}
