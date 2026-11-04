import XCTest
@testable import EQCore

final class LibraryTests: XCTestCase {
    private func preset(_ id: String, _ name: String) -> MusicPreset {
        MusicPreset(id: id, name: name, gains: MusicPreset.flat.gains, isBuiltIn: false)
    }

    func testMergeAddsOnlyNewAndKeepsLocal() {
        let local = PresetLibrary(presets: [preset("1", "Mine")])
        var remotePresetOne = preset("1", "Renamed elsewhere")
        remotePresetOne.gains[0] = 6
        let remote = PresetLibrary(presets: [remotePresetOne, preset("2", "From other Mac")],
                                   headphones: [HeadphoneProfile(id: "h", name: "Koss", kind: .onEar, filters: [], isBuiltIn: false)])
        let (merged, added) = local.merged(with: remote)
        XCTAssertEqual(added, 2)
        XCTAssertEqual(merged.presets.map(\.id), ["1", "2"])
        XCTAssertEqual(merged.presets[0].name, "Mine")        // local wins on conflicts
        XCTAssertEqual(merged.headphones.count, 1)
        XCTAssertEqual(merged.merged(with: remote).added, 0)  // idempotent
    }

    func testBuiltInsAreNeverExported() {
        let lib = PresetLibrary(presets: MusicPreset.builtIn + [preset("u", "Mine")], headphones: HeadphoneProfile.builtIn)
        XCTAssertEqual(lib.presets.map(\.id), ["u"])
        XCTAssertTrue(lib.headphones.isEmpty)
    }

    func testLibraryJSONRoundTrip() throws {
        let lib = PresetLibrary(presets: [preset("a", "A")], headphones: [], exportedAt: "2026-11-04")
        let back = try JSONDecoder().decode(PresetLibrary.self, from: JSONEncoder().encode(lib))
        XCTAssertEqual(back, lib)
        let item = PresetFormats.parse(text: String(data: try JSONEncoder().encode(lib), encoding: .utf8)!, fileName: "x.headeq", id: "n") {
            try? JSONDecoder().decode(PresetLibrary.self, from: Data($0.utf8))
        }
        XCTAssertEqual(item, .library(lib))
    }

    func testGraphicEQImportSamplesBands() {
        let text = "GraphicEQ: 20 6; 100 3; 1000 0; 10000 -3; 20000 -6"
        guard case .preset(let p)? = PresetFormats.parse(text: text, fileName: "Bright GraphicEQ.txt", id: "g", decodeJSON: { _ in nil }) else {
            return XCTFail("not parsed as preset")
        }
        XCTAssertEqual(p.name, "Bright")
        XCTAssertEqual(p.gains[5], 0, accuracy: 0.05)                  // 1 kHz
        XCTAssertGreaterThan(p.gains[0], 3); XCTAssertLessThan(p.gains[9], -3)
    }

    func testGraphicEQExportRoundTrip() {
        let filters = GraphicEQ.filters(gains: [0, 0, 0, 0, 0, 4, 0, 0, 0, 0])
        let line = PresetFormats.exportGraphicEQ(filters: filters, preamp: 0)
        XCTAssertTrue(line.hasPrefix("GraphicEQ: 20 "))
        let gains = PresetFormats.bandGains(fromGraphicEQ: PresetFormats.parseGraphicEQ(line))
        XCTAssertEqual(gains[5], 4, accuracy: 0.3)
        XCTAssertEqual(gains[0], 0, accuracy: 0.3)
    }

    func testParametricImportBecomesHeadphone() {
        let text = "Preamp: -6.2 dB\nFilter 1: ON LSC Fc 105 Hz Gain 5.6 dB Q 0.70\nFilter 2: ON PK Fc 3000 Hz Gain -2 dB Q 2"
        guard case .headphone(let h)? = PresetFormats.parse(text: text, fileName: "Sennheiser HD 650 ParametricEQ.txt", id: "p", decodeJSON: { _ in nil }) else {
            return XCTFail("not parsed as headphone")
        }
        XCTAssertEqual(h.name, "Sennheiser HD 650")
        XCTAssertEqual(h.filters.count, 2)
        XCTAssertEqual(h.matchKeywords, ["hd 650"])
        XCTAssertFalse(h.isBuiltIn)
    }

    func testGarbageIsRejected() {
        XCTAssertNil(PresetFormats.parse(text: "hello", fileName: "x.txt", id: "z", decodeJSON: { _ in nil }))
    }
}
