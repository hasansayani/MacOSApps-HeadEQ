import XCTest
@testable import EQCore

final class CompareTests: XCTestCase {
    func testBinomialPValues() {
        XCTAssertEqual(BlindTestSession.binomialTwoSided(k: 5, n: 10), 1, accuracy: 1e-9)
        XCTAssertEqual(BlindTestSession.binomialTwoSided(k: 8, n: 10), 0.109375, accuracy: 1e-6)
        XCTAssertEqual(BlindTestSession.binomialTwoSided(k: 9, n: 10), 0.021484375, accuracy: 1e-6)
        XCTAssertEqual(BlindTestSession.binomialTwoSided(k: 10, n: 10), 0.001953125, accuracy: 1e-9)
    }

    func testBlindSessionMapsOptionsToBothSlots() {
        var rng = SplitMix64(seed: 42)
        var s = BlindTestSession(trials: 20, rng: &rng)
        XCTAssertTrue(s.assignments.contains(.a) && s.assignments.contains(.b), "order should be randomised")
        while !s.isFinished {
            let one = s.slot(forOption: 1)!, two = s.slot(forOption: 2)!
            XCTAssertNotEqual(one, two)
            // Listener who always prefers B, wherever it's hidden.
            s.choose(option: one == .b ? 1 : 2)
        }
        XCTAssertEqual(s.countB, 20)
        XCTAssertLessThan(s.pValue, 0.001)
        XCTAssertTrue(s.verdict.contains("prefer B"))
    }

    func testGuessingGivesNoReliablePreference() {
        var rng = SplitMix64(seed: 7)
        var s = BlindTestSession(trials: 10, rng: &rng)
        while !s.isFinished { s.choose(option: 1) }   // always picks "1" → random slot
        XCTAssertGreaterThan(s.pValue, 0.05)
        XCTAssertTrue(s.verdict.hasPrefix("No reliable preference"))
    }

    func testLevelMatchingMeasuresAverageGain() {
        var flat = EQSettings(); flat.autoPreamp = false
        var boosted = flat; boosted.bandGains = Array(repeating: 6, count: 10)
        let a = SoundSnapshot(deviceName: "A", settings: flat)
        let b = SoundSnapshot(deviceName: "B", settings: boosted)
        let ga = a.averageGainDB(headphone: .none, base: flat)
        let gb = b.averageGainDB(headphone: .none, base: flat)
        XCTAssertEqual(ga, 0, accuracy: 0.1)
        XCTAssertGreaterThan(gb, 4)
    }

    func testSplitMixIsDeterministic() {
        var a = SplitMix64(seed: 1), b = SplitMix64(seed: 1)
        XCTAssertEqual((0..<5).map { _ in a.next() }, (0..<5).map { _ in b.next() })
    }
}
