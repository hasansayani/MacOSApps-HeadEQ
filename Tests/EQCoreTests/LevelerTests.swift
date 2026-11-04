import XCTest
@testable import EQCore

final class LevelerTests: XCTestCase {
    private let fs = 48_000.0

    /// Feed a 1 kHz stereo sine for `seconds`; return final gain and the output RMS (dBFS) of the last 0.5 s.
    private func run(amplitude: Float, seconds: Double, settings: LevelerSettings = { var s = LevelerSettings(); s.enabled = true; s.speed = .fast; return s }()) -> (gain: Float, lufs: Float) {
        let stage = LevelerStage()
        stage.params = settings.realtime(sampleRate: fs)
        let n = Int(seconds * fs)
        for i in 0..<n {
            var l = amplitude * Float(sin(2 * .pi * 1000 * Double(i) / fs)), r = l
            stage.process(&l, &r)
        }
        return (stage.currentGainDB, stage.loudnessLUFS)
    }

    func testQuietMaterialIsBoostedTowardTarget() {
        // ~-30 LUFS input, target -16, max boost 6 → boost saturates at +6.
        let r = run(amplitude: 0.03, seconds: 20)
        XCTAssertEqual(r.gain, 6, accuracy: 0.6)
    }

    func testLoudMaterialIsCut() {
        let r = run(amplitude: 0.9, seconds: 20)
        XCTAssertLessThan(r.gain, -3)
    }

    func testOnTargetIsLeftAlone() {
        // Find an amplitude that measures ≈ -16 LUFS, then check ~0 dB gain.
        var s = LevelerSettings(); s.enabled = true; s.speed = .fast; s.targetLUFS = -16
        let probe = run(amplitude: 0.2, seconds: 10, settings: s)
        var t = s; t.targetLUFS = Double(probe.lufs)    // target = what this signal measures
        let r = run(amplitude: 0.2, seconds: 20, settings: t)
        XCTAssertEqual(r.gain, 0, accuracy: 0.5)
    }

    func testSilenceIsNotBoosted() {
        let r = run(amplitude: 0.0001, seconds: 10)   // ~-80 LUFS: below the gate
        XCTAssertEqual(r.gain, 0, accuracy: 0.01)
    }

    func testKWeightingMatchesBS1770At1kHz() {
        // BS.1770: a 0 dBFS 1 kHz sine in ONE channel reads −3.01 LKFS.
        let stage = LevelerStage()
        var s = LevelerSettings(); s.speed = .fast
        stage.params = s.realtime(sampleRate: fs)
        for i in 0..<Int(5 * fs) {
            var l = Float(sin(2 * .pi * 1000 * Double(i) / fs)), r: Float = 0
            stage.process(&l, &r)
        }
        XCTAssertEqual(stage.loudnessLUFS, -3.01, accuracy: 0.3)
    }

    func testKWeightingCoefficientsMatchSpecAt48k() {
        // Reference values from ITU-R BS.1770-4, Table 1 & 2 (48 kHz).
        let s = BiquadCoefficients.kWeightingShelf(sampleRate: 48_000)
        XCTAssertEqual(s.b0, 1.53512485958697, accuracy: 1e-5)
        XCTAssertEqual(s.b1, -2.69169618940638, accuracy: 1e-5)
        XCTAssertEqual(s.b2, 1.19839281085285, accuracy: 1e-5)
        XCTAssertEqual(s.a1, -1.69065929318241, accuracy: 1e-5)
        XCTAssertEqual(s.a2, 0.73248077421585, accuracy: 1e-5)
        let h = BiquadCoefficients.kWeightingHighPass(sampleRate: 48_000)
        XCTAssertEqual(h.a1, -1.99004745483398, accuracy: 1e-5)
        XCTAssertEqual(h.a2, 0.99007225036621, accuracy: 1e-5)
    }

    func testHighPassFilter() {
        let c = BiquadCoefficients.highPass(100, q: 0.707, sampleRate: fs)
        XCTAssertEqual(c.magnitudeDB(at: 10_000, sampleRate: fs), 0, accuracy: 0.05)
        XCTAssertLessThan(c.magnitudeDB(at: 20, sampleRate: fs), -20)
    }
}
