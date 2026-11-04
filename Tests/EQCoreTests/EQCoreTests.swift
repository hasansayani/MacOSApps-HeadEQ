import XCTest
@testable import EQCore

final class EQCoreTests: XCTestCase {
    func testPeakFilterGainAtCenter() {
        let c = BiquadCoefficients(.peak(1000, 6, q: 1), sampleRate: 48_000)
        XCTAssertEqual(c.magnitudeDB(at: 1000, sampleRate: 48_000), 6, accuracy: 0.01)
        XCTAssertEqual(c.magnitudeDB(at: 20, sampleRate: 48_000), 0, accuracy: 0.1)
    }

    func testShelves() {
        let lo = BiquadCoefficients(.lowShelf(105, 5), sampleRate: 44_100)
        XCTAssertEqual(lo.magnitudeDB(at: 20, sampleRate: 44_100), 5, accuracy: 0.3)
        XCTAssertEqual(lo.magnitudeDB(at: 5000, sampleRate: 44_100), 0, accuracy: 0.1)
        let hi = BiquadCoefficients(.highShelf(10000, -3), sampleRate: 44_100)
        XCTAssertEqual(hi.magnitudeDB(at: 19000, sampleRate: 44_100), -3, accuracy: 0.4)
    }

    func testFlatIsIdentity() {
        let p = EQProcessor(maxChannels: 1)
        let coeffs = GraphicEQ.filters(gains: MusicPreset.flat.gains).map { BiquadCoefficients($0, sampleRate: 48_000) }
        coeffs.withUnsafeBufferPointer { p.apply($0, preampDB: 0) }
        var x: [Float] = (0..<256).map { sinf(Float($0) * 0.1) * 0.5 }
        let original = x
        x.withUnsafeMutableBufferPointer { p.process(channel: 0, samples: $0.baseAddress!, frames: $0.count) }
        for (a, b) in zip(x, original) { XCTAssertEqual(a, b, accuracy: 1e-6) }
    }

    func testProcessorMatchesDesignedGain() {
        let fs = 48_000.0, f = 1000.0
        let p = EQProcessor(maxChannels: 1)
        [BiquadCoefficients(.peak(f, 6, q: 1), sampleRate: fs)].withUnsafeBufferPointer { p.apply($0, preampDB: -6) }
        var x: [Float] = (0..<9600).map { Float(0.25 * sin(2 * .pi * f * Double($0) / fs)) }
        x.withUnsafeMutableBufferPointer { p.process(channel: 0, samples: $0.baseAddress!, frames: $0.count) }
        let peak = x.suffix(4800).map(abs).max()!
        XCTAssertEqual(peak, 0.25, accuracy: 0.01)   // +6 dB filter, -6 dB preamp
    }

    func testAutoPreampPreventsBoost() {
        var s = EQSettings()
        s.bandGains = MusicPreset.builtIn.first { $0.id == "bass" }!.gains
        let filters = s.filters(headphone: .none)
        let pre = s.effectivePreamp(filters: filters)
        XCTAssertLessThan(pre, -5)
        let curve = FrequencyResponse.curve(filters: filters, preamp: pre, frequencies: FrequencyResponse.logFrequencies())
        XCTAssertLessThanOrEqual(curve.max()!, 0.05)
    }

    func testHeadphoneMatching() {
        XCTAssertEqual(HeadphoneProfile.match(deviceName: "Hasan's AirPods Pro")?.id, "airpods-pro-2")
        XCTAssertEqual(HeadphoneProfile.match(deviceName: "AirPods Max")?.id, "airpods-max")
        XCTAssertEqual(HeadphoneProfile.match(deviceName: "AirPods")?.id, "airpods")
        XCTAssertEqual(HeadphoneProfile.match(deviceName: "WH-1000XM5")?.id, "sony-xm5")
        XCTAssertNil(HeadphoneProfile.match(deviceName: "MacBook Pro Speakers"))
    }

    func testAllProfilesFitProcessor() {
        for h in HeadphoneProfile.builtIn {
            XCTAssertLessThanOrEqual(h.filters.count + GraphicEQ.frequencies.count, EQProcessor.maxFilters)
        }
    }
}
