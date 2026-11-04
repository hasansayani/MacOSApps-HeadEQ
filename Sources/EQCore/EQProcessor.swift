/// Real-time EQ processor: a cascade of biquads (Transposed Direct Form II)
/// per channel, followed by a stereo output stage (see `OutputSettings`).
///
/// Threading: `process*` and `apply*` must be called from the same (audio)
/// thread. Platform backends deliver new parameters through their own
/// lock-free/try-lock mailbox and call `apply*` at the start of a render
/// cycle. Nothing here allocates memory.
public final class EQProcessor {
    public static let maxFilters = 32
    public let maxChannels: Int

    private let coeffs: UnsafeMutablePointer<BiquadCoefficients>
    private let state: UnsafeMutablePointer<Float>   // [channel][filter][z1,z2]
    private var filterCount = 0
    private var preampLinear: Float = 1

    private var output = RealtimeOutput()
    private var lpL: Float = 0, lpR: Float = 0      // crossfeed low-pass state
    private var limiterGain: Float = 1
    private var guardState = HearingGuard()
    /// Optional stages (only allocated for features that are on).
    private var stages: StageSet?
    /// Hearing-protection gain reduction (dB, ≤ 0) and output level (dBFS RMS). For metering.
    public var protectionReductionDB: Float { guardState.reductionDB }
    public var outputLevelDBFS: Float { guardState.outputLevelDBFS }
    /// Most recent gain reduction applied by the limiter, in dB (≤ 0). For metering.
    public private(set) var limiterReductionDB: Float = 0

    public init(maxChannels: Int = 8) {
        self.maxChannels = maxChannels
        coeffs = .allocate(capacity: Self.maxFilters)
        coeffs.initialize(repeating: .identity, count: Self.maxFilters)
        let n = maxChannels * Self.maxFilters * 2
        state = .allocate(capacity: n)
        state.initialize(repeating: 0, count: n)
    }

    deinit {
        coeffs.deallocate()
        state.deallocate()
    }

    /// Install new coefficients. Keeps filter state for continuity; clears
    /// state for filter slots that were previously unused.
    public func apply(_ new: UnsafeBufferPointer<BiquadCoefficients>, preampDB: Float) {
        let count = min(new.count, Self.maxFilters)
        for i in 0..<count { coeffs[i] = new[i] }
        if count > filterCount {
            for ch in 0..<maxChannels {
                for i in filterCount..<count {
                    state[(ch * Self.maxFilters + i) * 2] = 0
                    state[(ch * Self.maxFilters + i) * 2 + 1] = 0
                }
            }
        }
        filterCount = count
        preampLinear = powf(10, preampDB / 20)
    }

    public func applyOutput(_ params: RealtimeOutput) { output = params }
    public func applyHearing(_ params: RealtimeHearing) { guardState.params = params }

    /// Swap in a new stage set; returns the previous one so the caller can
    /// release it off the audio thread.
    public func installStages(_ new: StageSet?) -> StageSet? {
        let old = stages
        stages = new
        return old
    }

    public func applyStageParams(_ p: StageParams) {
        stages?.surround?.params = p.surround
        stages?.leveler?.params = p.leveler
    }

    /// Levelling meters (0 / silence when the feature is off).
    public var levelerGainDB: Float { stages?.leveler?.currentGainDB ?? 0 }
    public var loudnessLUFS: Float { stages?.leveler?.loudnessLUFS ?? -120 }

    public func reset() {
        state.update(repeating: 0, count: maxChannels * Self.maxFilters * 2)
        lpL = 0; lpR = 0; limiterGain = 1
        let params = guardState.params
        guardState = HearingGuard()
        guardState.params = params
    }

    /// EQ only: process `frames` samples of one channel in place.
    public func process(channel: Int, samples: UnsafeMutablePointer<Float>, frames: Int) {
        guard channel < maxChannels else { return }
        let g = preampLinear
        let n = filterCount
        let st = state + channel * Self.maxFilters * 2
        for t in 0..<frames {
            var x = samples[t] * g
            for i in 0..<n {
                let c = coeffs[i]
                let z = st + i * 2
                let y = c.b0 * x + z[0]
                z[0] = c.b1 * x - c.a1 * y + z[1]
                z[1] = c.b2 * x - c.a2 * y
                x = y
            }
            samples[t] = x
        }
        // Flush denormals that build up in silence.
        for i in 0..<(n * 2) where abs(st[i]) < 1e-20 { st[i] = 0 }
    }

    /// Full chain: EQ on each channel, then the stereo output stage.
    /// Pass `right == nil` for mono material.
    public func processStereo(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>?, frames: Int) {
        process(channel: 0, samples: left, frames: frames)
        if let right { process(channel: 1, samples: right, frames: frames) }

        let o = output
        let surround = right != nil ? stages?.surround : nil
        let leveler = stages?.leveler
        var minGain: Float = 1
        for t in 0..<frames {
            var l = left[t]
            var r = right?[t] ?? l

            surround?.process(&l, &r)

            if o.swap { swap(&l, &r) }
            if o.crossfeed > 0 {
                lpL += o.crossfeedCoef * (l - lpL)
                lpR += o.crossfeedCoef * (r - lpR)
                let norm = 1 / (1 + o.crossfeed)
                (l, r) = ((l + o.crossfeed * lpR) * norm, (r + o.crossfeed * lpL) * norm)
            }
            if o.width != 1 {
                let m = (l + r) * 0.5, s = (l - r) * 0.5 * o.width
                l = m + s; r = m - s
            }
            if o.balance > 0 { l *= 1 - o.balance } else if o.balance < 0 { r *= 1 + o.balance }
            let g = o.gain * o.polarity
            l *= g; r *= g

            leveler?.process(&l, &r)
            guardState.process(&l, &r)

            if o.limiter {
                let peak = max(abs(l), abs(r))
                let target: Float = peak > o.ceiling ? o.ceiling / peak : 1
                if target < limiterGain { limiterGain = target }
                else { limiterGain += (target - limiterGain) * o.release }
                l *= limiterGain; r *= limiterGain
                minGain = min(minGain, limiterGain)
                l = max(-o.ceiling, min(o.ceiling, l))
                r = max(-o.ceiling, min(o.ceiling, r))
            } else {
                l = max(-1, min(1, l)); r = max(-1, min(1, r))
            }
            left[t] = l
            right?[t] = r
        }
        if abs(lpL) < 1e-20 { lpL = 0 }
        if abs(lpR) < 1e-20 { lpR = 0 }
        limiterReductionDB = 20 * log10f(max(minGain, 1e-6))
    }
}
