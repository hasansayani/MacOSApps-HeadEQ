import XCTest
@testable import EQCore

final class SurroundTests: XCTestCase {
    private func impulseResponse(_ s: SurroundSettings, frames: Int = 2048) -> (l: [Float], r: [Float]) {
        let stage = SurroundStage()
        stage.params = s.realtime(sampleRate: 48_000)
        var L = [Float](repeating: 0, count: frames), R = L
        for t in 0..<frames {
            var l: Float = t == 0 ? 1 : 0, r: Float = 0
            stage.process(&l, &r)
            L[t] = l; R[t] = r
        }
        return (L, R)
    }

    func testOppositeEarIsDelayedByITD() {
        var s = SurroundSettings(); s.room = 0; s.speakerAngle = 30
        let ir = impulseResponse(s)
        let itd = Int((s.itdSeconds * 48_000).rounded())
        XCTAssertGreaterThan(ir.l[0], 0.5)                     // direct path, immediate
        XCTAssertEqual(ir.r[..<itd].map(abs).max()!, 0, accuracy: 1e-7)   // nothing before the ITD
        XCTAssertGreaterThan(ir.r.map(abs).max()!, 0.01)       // the opposite ear does hear it
        XCTAssertEqual(s.itdSeconds * 1000, 0.26, accuracy: 0.03)  // ~0.26 ms at ±30°
    }

    func testRoomAddsLateEnergy() {
        var dry = SurroundSettings(); dry.room = 0
        var wet = SurroundSettings(); wet.room = 1
        let late = { (ir: (l: [Float], r: [Float])) in ir.l[300...].map(abs).reduce(0, +) }
        XCTAssertGreaterThan(late(impulseResponse(wet)), late(impulseResponse(dry)) * 5)
    }

    func testCentredContentKeepsLevel() {
        let stage = SurroundStage()
        var s = SurroundSettings(); s.room = 0
        stage.params = s.realtime(sampleRate: 48_000)
        var out: Float = 0
        for _ in 0..<4800 { var l: Float = 0.5, r: Float = 0.5; stage.process(&l, &r); out = l }
        XCTAssertEqual(out, 0.5, accuracy: 0.08)
    }

    func testOffMeansNoStageAllocated() {
        var f = FeatureSettings()
        XCTAssertNil(f.processing.surround)
        XCTAssertTrue(f.processing.signature.isEmpty)
        f[isOn: "surround"] = true
        XCTAssertNotNil(f.processing.surround)
        XCTAssertNotNil(StageSet(surround: true).surround)
        XCTAssertNil(StageSet(surround: false).surround)
    }

    func testProcessorRunsSurroundOnlyWhenInstalled() {
        let p = EQProcessor(maxChannels: 2)
        var o = OutputSettings(); o.limiterEnabled = false
        p.applyOutput(o.realtime(sampleRate: 48_000))
        var L: [Float] = [1] + [Float](repeating: 0, count: 63), R = [Float](repeating: 0, count: 64)
        L.withUnsafeMutableBufferPointer { l in R.withUnsafeMutableBufferPointer { r in
            p.processStereo(left: l.baseAddress!, right: r.baseAddress!, frames: 64) } }
        XCTAssertEqual(R.map(abs).max()!, 0)    // no stage → channels stay separate

        _ = p.installStages(StageSet(surround: true))
        var params = StageParams(); params.surround = SurroundSettings().realtime(sampleRate: 48_000)
        p.applyStageParams(params)
        L = [1] + [Float](repeating: 0, count: 63); R = [Float](repeating: 0, count: 64)
        L.withUnsafeMutableBufferPointer { l in R.withUnsafeMutableBufferPointer { r in
            p.processStereo(left: l.baseAddress!, right: r.baseAddress!, frames: 64) } }
        XCTAssertGreaterThan(R.map(abs).max()!, 0.01)
    }
}
