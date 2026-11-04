import XCTest
@testable import EQCore

final class HearingTestTests: XCTestCase {
    /// Simulated listener who hears anything at or above their threshold.
    private func runTest(thresholds: [Ear: [Double: Double]]) -> Audiogram {
        var s = HearingTestSession()
        var guardCount = 0
        while let p = s.current, guardCount < 2000 {
            let t = thresholds[p.ear]?[p.frequency] ?? -60
            s.respond(heard: p.levelDBFS >= t)
            guardCount += 1
        }
        XCTAssertTrue(s.isFinished)
        XCTAssertEqual(s.progress, 1)
        return s.audiogram
    }

    func testStaircaseFindsThresholdWithin5dB() {
        let left: [Double: Double] = [1000: -62, 2000: -58, 4000: -50, 6000: -44, 8000: -38, 500: -60, 250: -55]
        let right: [Double: Double] = [1000: -63, 2000: -60, 4000: -57, 6000: -55, 8000: -52, 500: -61, 250: -56]
        let a = runTest(thresholds: [.left: left, .right: right])
        XCTAssertEqual(a.left.count, 7)
        XCTAssertEqual(a.right.count, 7)
        for p in a.left { XCTAssertEqual(p.thresholdDBFS, left[p.frequency]!, accuracy: 5, "left \(p.frequency)") }
        for p in a.right { XCTAssertEqual(p.thresholdDBFS, right[p.frequency]!, accuracy: 5, "right \(p.frequency)") }
    }

    func testDeafAtFrequencyClampsAtMaxLevel() {
        let a = runTest(thresholds: [.left: [8000: 0], .right: [:]])   // can't hear 8 kHz at all on the left
        XCTAssertEqual(a.points(.left).first { $0.frequency == 8000 }!.thresholdDBFS, HearingTestSession.maxLevel)
    }

    func testCorrectionBoostsWeakFrequenciesPerEar() {
        let a = Audiogram(
            left: [.init(frequency: 1000, thresholdDBFS: -60), .init(frequency: 4000, thresholdDBFS: -40)],
            right: [.init(frequency: 1000, thresholdDBFS: -60), .init(frequency: 4000, thresholdDBFS: -60)])
        XCTAssertEqual(a.reference, -60)
        let left = a.correction(.left, strength: 0.5, maxBoostDB: 15)
        XCTAssertEqual(left.count, 1)
        XCTAssertEqual(left[0].frequency, 4000)
        XCTAssertEqual(left[0].gain, 10, accuracy: 0.01)      // half of 20 dB
        XCTAssertTrue(a.correction(.right, strength: 0.5, maxBoostDB: 15).isEmpty)
        XCTAssertEqual(a.correction(.left, strength: 1, maxBoostDB: 6)[0].gain, 6)   // capped
    }

    func testPersonalStageIsPerEarAndClipSafe() {
        var s = PersonalCorrectionSettings(); s.enabled = true
        s.audiogram = Audiogram(left: [.init(frequency: 1000, thresholdDBFS: -40)],
                                right: [.init(frequency: 1000, thresholdDBFS: -60)])
        let stage = PersonalEQStage()
        stage.params = s.realtime(sampleRate: 48_000)
        var peakL: Float = 0, peakR: Float = 0
        for i in 0..<9600 {
            let x = Float(0.5 * sin(2 * .pi * 1000 * Double(i) / 48_000))
            var l = x, r = x
            stage.process(&l, &r)
            if i > 4800 { peakL = max(peakL, abs(l)); peakR = max(peakR, abs(r)) }
        }
        XCTAssertEqual(peakL, 0.5, accuracy: 0.03)            // boosted ear restored to unity by the preamp
        XCTAssertLessThan(peakR, peakL * 0.5)                 // other ear stays relatively quieter (no boost)
    }

    func testStageOnlyAllocatedWithResults() {
        var f = FeatureSettings()
        f.personal.enabled = true
        XCTAssertNil(f.processing.personal)                    // on, but nothing to apply yet
        f.personal.audiogram = Audiogram(left: [.init(frequency: 1000, thresholdDBFS: -50)])
        XCTAssertNotNil(f.processing.personal)
    }

    func testBiquad8InlineStorage() {
        var b = Biquad8()
        for i in 0..<8 { b[i] = BiquadCoefficients(b0: Float(i), b1: 0, b2: 0, a1: 0, a2: 0) }
        for i in 0..<8 { XCTAssertEqual(b[i].b0, Float(i)) }
    }
}
