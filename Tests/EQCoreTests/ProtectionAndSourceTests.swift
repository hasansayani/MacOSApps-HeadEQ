import XCTest
@testable import EQCore

final class SourceTests: XCTestCase {
    func testXM3ProfileIsMeasured() {
        let p = HeadphoneProfile.builtIn.first { $0.id == "sony-xm3" }!
        XCTAssertEqual(p.kind, .overEar)
        XCTAssertEqual(p.provenance.kind, .measured)
        XCTAssertEqual(p.provenance.measuredBy, "oratory1990")
        XCTAssertEqual(HeadphoneProfile.match(deviceName: "WH-1000XM3")?.id, "sony-xm3")
        XCTAssertEqual(PresetGenerator.generate(from: "pop on my sony xm3 overhead").headphone?.id, "sony-xm3")
        XCTAssertEqual(HeadphoneProfile.match(deviceName: "WF-1000XM5")?.id, "sony-wf-xm5")
    }

    func testApproximationsAreLabelled() {
        XCTAssertEqual(HeadphoneProfile.builtIn.first { $0.id == "sony-xm4" }!.provenance.kind, .approximation)
        XCTAssertEqual(HeadphoneProfile.builtIn.first { $0.id == "generic-over" }!.provenance.kind, .generic)
    }

    func testParseIndexAndSearch() {
        let index = """
        # Index
        - [Sony WH-1000XM3](./oratory1990/over-ear/Sony%20WH-1000XM3) by oratory1990
        - [Sony WH-1000XM3](./Rtings/HMS%20II.3%20over-ear/Sony%20WH-1000XM3) by Rtings on HMS II.3
        - [Sony WH-1000XM3 (ANC off)](./Kuulokenurkka/over-ear/Sony%20WH-1000XM3%20(ANC%20off)) by Kuulokenurkka
        - [Sony WF-1000XM3](./crinacle/711%20in-ear/Sony%20WF-1000XM3) by crinacle on 711
        """
        let entries = AutoEQ.parseIndex(index)
        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(entries[3].kind, .inEar)
        let results = AutoEQ.search("sony wh-1000xm3", in: entries)
        XCTAssertEqual(results.first?.source, "oratory1990")
        XCTAssertEqual(results.first?.parametricEQURL,
                       AutoEQ.baseURL + "oratory1990/over-ear/Sony%20WH-1000XM3/Sony%20WH-1000XM3%20ParametricEQ.txt")
        XCTAssertFalse(results.contains { $0.name == "Sony WF-1000XM3" })
    }

    func testParseParametricAndRoundTrip() {
        let text = """
        Preamp: -5.3 dB
        Filter 1: ON LSC Fc 105 Hz Gain -4.1 dB Q 0.70
        Filter 2: ON PK Fc 143 Hz Gain -5.9 dB Q 1.02
        Filter 3: OFF PK Fc 1000 Hz Gain 3 dB Q 1
        Filter 4: ON HSC Fc 10000 Hz Gain 1.4 dB Q 0.70
        """
        let parsed = AutoEQ.parseParametricEQ(text)
        XCTAssertEqual(parsed.preamp, -5.3)
        XCTAssertEqual(parsed.filters, [.lowShelf(105, -4.1, q: 0.7), .peak(143, -5.9, q: 1.02), .highShelf(10000, 1.4, q: 0.7)])
        let again = AutoEQ.parseParametricEQ(AutoEQ.exportParametricEQ(filters: parsed.filters, preamp: parsed.preamp))
        XCTAssertEqual(again.filters, parsed.filters)
    }

    func testStarterProfileFromName() {
        let p = HeadphoneNaming.starterProfile(named: "Jabra Elite 85t", id: "x")
        XCTAssertEqual(p.kind, .inEar)
        XCTAssertEqual(p.matchKeywords, ["elite 85t"])
        XCTAssertEqual(p.provenance.kind, .generic)
        XCTAssertEqual(HeadphoneNaming.guessKind("Sennheiser Momentum 4"), .overEar)
    }

    func testOldCustomHeadphoneJSONDecodes() throws {
        let json = #"{"id":"user-hp-1","name":"Mine","kind":"Over-ear","matchKeywords":[],"filters":[],"note":"","isBuiltIn":false}"#
        let p = try JSONDecoder().decode(HeadphoneProfile.self, from: Data(json.utf8))
        XCTAssertNil(p.source)
        XCTAssertEqual(p.provenance.kind, .userCreated)
    }
}

final class HearingTests: XCTestCase {
    private let fs = 48_000.0

    /// Runs a stereo sine whose amplitude changes per segment; returns the
    /// peak output in the last 100 ms of each segment.
    private func run(_ segments: [(amp: Float, seconds: Double)], hearing: HearingProtectionSettings, capDBFS: Double = 0) -> [Float] {
        let p = EQProcessor(maxChannels: 2)
        var out = OutputSettings(); out.limiterEnabled = false
        p.applyOutput(out.realtime(sampleRate: fs))
        p.applyHearing(hearing.realtime(sampleRate: fs, capDBFS: capDBFS))
        var peaks: [Float] = []
        var phase = 0.0
        for seg in segments {
            let n = Int(seg.seconds * fs)
            var l = [Float](repeating: 0, count: n)
            for i in 0..<n { l[i] = seg.amp * Float(sin(phase)); phase += 2 * .pi * 440 / fs }
            var r = l
            l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in
                p.processStereo(left: lp.baseAddress!, right: rp.baseAddress!, frames: n)
            } }
            peaks.append(l.suffix(Int(0.1 * fs)).map(abs).max()!)
        }
        return peaks
    }

    func testSteadyMusicUntouched() {
        var h = HearingProtectionSettings(); h.levelCap = false
        let peaks = run([(0.3, 5)], hearing: h)
        XCTAssertEqual(peaks[0], 0.3, accuracy: 0.003)
    }

    func testSuddenSpikeIsReducedThenAccepted() {
        var h = HearingProtectionSettings(); h.levelCap = false; h.spikeThresholdDB = 10
        // 5 s quiet (-40 dB), then a +32 dB blast.
        let peaks = run([(0.01, 5), (0.4, 0.3), (0.4, 15)], hearing: h)
        XCTAssertLessThan(peaks[1], 0.4 * 0.5, "spike should be pulled down by > 6 dB")
        XCTAssertGreaterThan(peaks[2], 0.4 * 0.85, "sustained new level is eventually accepted")
    }

    func testMusicalDynamicsUntouched() {
        var h = HearingProtectionSettings(); h.levelCap = false
        // Quiet verse → chorus/drop 8 dB louder: below the 10 dB trigger.
        let peaks = run([(0.1, 6), (0.25, 0.5)], hearing: h)
        XCTAssertEqual(peaks[1], 0.25, accuracy: 0.003)
    }

    func testLevelCapRidesSustainedLevelDown() {
        var h = HearingProtectionSettings(); h.spikeGuard = false
        // Cap at -20 dBFS RMS; signal ≈ -9 dBFS RMS.
        let peaks = run([(0.5, 20)], hearing: h, capDBFS: -20)
        let rmsDB = 20 * log10(Double(peaks[0]) / 2.0.squareRoot())
        XCTAssertEqual(rmsDB, -20, accuracy: 1.5)
    }

    func testDisabledIsBitTransparent() {
        var h = HearingProtectionSettings(); h.enabled = false
        let peaks = run([(0.01, 2), (0.9, 1)], hearing: h, capDBFS: -40)
        XCTAssertEqual(peaks[1], 0.9, accuracy: 0.002)
    }

    func testExposureMath() {
        var m = ExposureMeter(day: 1)
        m.add(spl: 85, seconds: 8 * 3600)
        XCTAssertEqual(m.dose, 1, accuracy: 1e-9)
        var m2 = ExposureMeter(day: 1)
        m2.add(spl: 88, seconds: 4 * 3600)
        XCTAssertEqual(m2.dose, 1, accuracy: 1e-9)
        var m3 = ExposureMeter(day: 1)
        m3.add(spl: 30, seconds: 3600)
        XCTAssertEqual(m3.dose, 0)
        XCTAssertEqual(ExposureMeter(day: 1).remainingSeconds(atSPL: 94)!, 3600, accuracy: 1)
    }

    func testCapAccountsForVolumeAndDose() {
        let h = HearingProtectionSettings()   // 90 dB cap, 100 dB sensitivity, -5 dB when over dose
        XCTAssertEqual(h.capDBFS(deviceVolumeDB: 0, doseFraction: 0.2), -10)
        XCTAssertEqual(h.capDBFS(deviceVolumeDB: -20, doseFraction: 0.2), 10)
        XCTAssertEqual(h.capDBFS(deviceVolumeDB: 0, doseFraction: 1.1), -15)
    }
}
