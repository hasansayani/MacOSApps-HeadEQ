import EQCore
import Foundation

/// `HEADEQ_BENCHMARK=<out.json> HeadEQ` times the real-time DSP chain offline
/// (no audio device) and writes the results for scripts/app_facts.py.
enum DSPBenchmark {
    static func runIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["HEADEQ_BENCHMARK"], !path.isEmpty else { return }
        let result = run()
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
        exit(0)
    }

    static func run(frames: Int = 480, runs: Int = 2000, sampleRate: Double = 48_000) -> [String: Any] {
        var settings = EQSettings()
        settings.headphoneProfileID = "sony-xm3"
        settings.bandGains = MusicPreset.builtIn.first { $0.id == "electronic" }!.gains
        let headphone = HeadphoneProfile.builtIn(measured: true).first { $0.id == "sony-xm3" }!
        let filters = settings.filters(headphone: headphone)

        func time(_ config: ProcessingConfig) -> [Double] {
            let p = EQProcessor(maxChannels: 2)
            let coeffs = filters.map { BiquadCoefficients($0, sampleRate: sampleRate) }
            coeffs.withUnsafeBufferPointer { p.apply($0, preampDB: Float(settings.effectivePreamp(filters: filters))) }
            p.applyOutput(settings.output.realtime(sampleRate: sampleRate))
            p.applyHearing(settings.hearing.realtime(sampleRate: sampleRate, capDBFS: -10))
            if !config.signature.isEmpty {
                _ = p.installStages(StageSet(config.signature))
                p.applyStageParams(config.realtime(sampleRate: sampleRate))
            }
            let l = UnsafeMutablePointer<Float>.allocate(capacity: frames), r = UnsafeMutablePointer<Float>.allocate(capacity: frames)
            defer { l.deallocate(); r.deallocate() }
            var phase = 0.0
            var out: [Double] = []
            out.reserveCapacity(runs)
            for i in 0..<(runs + 200) {
                for t in 0..<frames {                       // pink-ish test signal: two tones + noise
                    phase += 2 * Double.pi * 220 / sampleRate
                    let x = Float(0.3 * sin(phase) + 0.1 * sin(phase * 7.3)) + Float.random(in: -0.05...0.05)
                    l[t] = x; r[t] = x * 0.9
                }
                let start = DispatchTime.now().uptimeNanoseconds
                p.processStereo(left: l, right: r, frames: frames)
                let ns = DispatchTime.now().uptimeNanoseconds - start
                if i >= 200 { out.append(Double(ns) / 1_000_000) }   // skip warm-up
            }
            return out.sorted()
        }

        var all = ProcessingConfig()
        all.surround = { var s = SurroundSettings(); s.enabled = true; return s }()
        all.leveler = { var s = LevelerSettings(); s.enabled = true; return s }()
        all.personal = {
            var s = PersonalCorrectionSettings(); s.enabled = true
            s.audiogram = Audiogram(left: HearingTestSession.frequencies.map { .init(frequency: $0, thresholdDBFS: $0 > 3000 ? -45 : -60) },
                                    right: HearingTestSession.frequencies.map { .init(frequency: $0, thresholdDBFS: -60) })
            return s
        }()

        let base = time(ProcessingConfig())
        let full = time(all)
        func pct(_ a: [Double], _ q: Double) -> Double { a[min(a.count - 1, Int(Double(a.count) * q))] }
        let bufferMS = Double(frames) / sampleRate * 1000
        let load = pct(full, 0.5) / bufferMS * 100
        func r3(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }
        return [
            "median_ms": r3(pct(full, 0.5)),
            "p95_ms": r3(pct(full, 0.95)),
            "runs": runs,
            "frames": frames,
            "filters": filters.count,
            "extra": [
                ["Base chain (optional features off)", "\(r3(pct(base, 0.5))) ms median"],
                ["Real-time load, everything on", String(format: "%.2f%% of one core", load)],
            ],
        ]
    }
}
