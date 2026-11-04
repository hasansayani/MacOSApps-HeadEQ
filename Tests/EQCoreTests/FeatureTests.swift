import XCTest
@testable import EQCore

final class GeneratorTests: XCTestCase {
    func testEDMOnBoseSoundSport() {
        let g = PresetGenerator.generate(from: "I am listening EDM through Bose sound sport")
        XCTAssertEqual(g.headphone?.id, "bose-soundsport")
        let electronic = MusicPreset.builtIn.first { $0.id == "electronic" }!
        XCTAssertEqual(g.gains, electronic.gains)
        XCTAssertTrue(g.understood.contains { $0.contains("Electronic") })
        XCTAssertEqual(g.name, "Electronic · Bose SoundSport / SoundSport Free")
    }

    func testModifiersStack() {
        let base = PresetGenerator.generate(from: "hip hop on airpods pro")
        let more = PresetGenerator.generate(from: "hip hop on airpods pro, more bass but not harsh")
        XCTAssertEqual(more.headphone?.id, "airpods-pro-2")
        XCTAssertGreaterThan(more.gains[0], base.gains[0])
        XCTAssertLessThan(more.gains[8], base.gains[8])
    }

    func testLessBassWinsOverBass() {
        let g = PresetGenerator.generate(from: "rock, less bass")
        let rock = MusicPreset.builtIn.first { $0.id == "rock" }!
        XCTAssertLessThan(g.gains[0], rock.gains[0])
    }

    func testGenericTypeFallback() {
        XCTAssertEqual(PresetGenerator.generate(from: "jazz on cheap earbuds").headphone?.id, "generic-earbud")
        XCTAssertNil(PresetGenerator.generate(from: "something").headphone)
    }

    func testCustomHeadphoneMatchedByName() {
        let mine = HeadphoneProfile(id: "user-hp-1", name: "Koss Porta Pro", kind: .onEar, filters: [], isBuiltIn: false)
        let g = PresetGenerator.generate(from: "pop on my Koss Porta Pro", headphones: [mine] + HeadphoneProfile.builtIn)
        XCTAssertEqual(g.headphone?.id, "user-hp-1")
    }

    func testGainsClamped() {
        let g = PresetGenerator.generate(from: "edm workout party more bass bassy")
        XCTAssertTrue(g.gains.allSatisfy { GraphicEQ.gainRange.contains($0) })
    }
}

final class OutputStageTests: XCTestCase {
    private func run(_ o: OutputSettings, l: Float, r: Float, frames: Int = 64) -> (Float, Float) {
        let p = EQProcessor(maxChannels: 2)
        p.applyOutput(o.realtime(sampleRate: 48_000))
        var L = [Float](repeating: l, count: frames), R = [Float](repeating: r, count: frames)
        L.withUnsafeMutableBufferPointer { lp in R.withUnsafeMutableBufferPointer { rp in
            p.processStereo(left: lp.baseAddress!, right: rp.baseAddress!, frames: frames)
        } }
        return (L.last!, R.last!)
    }

    func testDefaultsArePassThrough() {
        let (l, r) = run(OutputSettings(), l: 0.3, r: -0.2)
        XCTAssertEqual(l, 0.3, accuracy: 1e-6); XCTAssertEqual(r, -0.2, accuracy: 1e-6)
    }

    func testMonoSwapBalancePolarity() {
        var o = OutputSettings(); o.mono = true
        var (l, r) = run(o, l: 0.4, r: 0.0)
        XCTAssertEqual(l, 0.2, accuracy: 1e-6); XCTAssertEqual(r, 0.2, accuracy: 1e-6)

        o = OutputSettings(); o.swapChannels = true
        (l, r) = run(o, l: 0.4, r: 0.1)
        XCTAssertEqual(l, 0.1, accuracy: 1e-6); XCTAssertEqual(r, 0.4, accuracy: 1e-6)

        o = OutputSettings(); o.balance = 0.5
        (l, r) = run(o, l: 0.4, r: 0.4)
        XCTAssertEqual(l, 0.2, accuracy: 1e-6); XCTAssertEqual(r, 0.4, accuracy: 1e-6)

        o = OutputSettings(); o.invertPolarity = true
        (l, _) = run(o, l: 0.4, r: 0.4)
        XCTAssertEqual(l, -0.4, accuracy: 1e-6)
    }

    func testLimiterHoldsCeiling() {
        var o = OutputSettings(); o.gainDB = 6; o.limiterCeilingDB = -1
        let (l, _) = run(o, l: 0.9, r: 0.9)
        XCTAssertLessThanOrEqual(l, Float(pow(10, -1.0 / 20)) + 1e-5)
    }

    func testCrossfeedBleedsIntoOtherChannel() {
        var o = OutputSettings(); o.crossfeed = 1
        let (_, r) = run(o, l: 0.5, r: 0, frames: 4800)   // DC settles through the low-pass
        XCTAssertGreaterThan(r, 0.1)
    }

    func testOldSettingsJSONStillDecodes() throws {
        let old = #"{"enabled":true,"headphoneProfileID":"none","autoDetectHeadphones":true,"musicPresetID":"flat","bandGains":[0,0,0,0,0,0,0,0,0,0],"preampDB":0,"autoPreamp":true}"#
        let s = try JSONDecoder().decode(EQSettings.self, from: Data(old.utf8))
        XCTAssertEqual(s.output, OutputSettings())
        XCTAssertEqual(s.graphicQ, GraphicEQ.q)
    }
}

final class AnalyzerTests: XCTestCase {
    func testSinePeaksInRightBand() {
        let a = SpectrumAnalyzer(fftSize: 2048, bandCount: 32)
        let fs = 48_000.0
        let x = (0..<2048).map { Float(0.5 * sin(2 * .pi * 1000 * Double($0) / fs)) }
        for _ in 0..<30 { x.withUnsafeBufferPointer { a.process($0, sampleRate: fs, dt: 1.0 / 30) } }
        let loudest = a.levels.indices.max { a.levels[$0] < a.levels[$1] }!
        // Band containing 1 kHz on a 30 Hz…18 kHz log scale.
        let expected = Int(log(1000 / 30.0) / log(18_000 / 30.0) * 32)
        XCTAssertLessThanOrEqual(abs(loudest - expected), 1)
        XCTAssertGreaterThan(a.levels[loudest], 0.7)
    }

    func testRingReturnsNewestSamples() {
        let ring = SampleRing(capacity: 16)
        let l: [Float] = (0..<20).map(Float.init)
        l.withUnsafeBufferPointer { ring.writeMix($0.baseAddress!, nil, frames: 20) }
        var out = [Float](repeating: 0, count: 4)
        out.withUnsafeMutableBufferPointer { ring.copyLatest(into: $0) }
        XCTAssertEqual(out, [16, 17, 18, 19])
    }
}
