/// Volume levelling: evens out loudness between tracks, apps and videos.
/// Loudness is measured like ITU-R BS.1770 (K-weighting, summed channel
/// power, LUFS) over a sliding window, and a slow, broadband gain ride moves
/// it toward the target — so dynamics *within* a track are preserved.

public struct LevelerSettings: Codable, Equatable, Sendable {
    public enum Speed: String, Codable, CaseIterable, Sendable {
        case slow, medium, fast
        public var windowSeconds: Double { self == .slow ? 6 : self == .medium ? 3 : 1.5 }
        public var title: String { self == .slow ? "Slow" : self == .medium ? "Medium" : "Fast" }
    }

    public var enabled = false
    public var targetLUFS: Double = -16       // streaming-style loudness
    public var maxBoostDB: Double = 6
    public var maxCutDB: Double = 12
    public var speed: Speed = .medium

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LevelerSettings()
        enabled = c.value(.enabled, d.enabled)
        targetLUFS = c.value(.targetLUFS, d.targetLUFS)
        maxBoostDB = c.value(.maxBoostDB, d.maxBoostDB)
        maxCutDB = c.value(.maxCutDB, d.maxCutDB)
        speed = c.value(.speed, d.speed)
    }

    public func realtime(sampleRate: Double) -> RealtimeLeveler {
        let block = Double(LevelerStage.blockSize) / sampleRate
        var r = RealtimeLeveler()
        r.shelf = BiquadCoefficients.kWeightingShelf(sampleRate: sampleRate)
        r.highPass = BiquadCoefficients.kWeightingHighPass(sampleRate: sampleRate)
        r.powerCoef = Float(1 - exp(-1 / (speed.windowSeconds * sampleRate)))
        r.target = Float(targetLUFS)
        r.maxBoost = Float(max(0, maxBoostDB))
        r.maxCut = Float(max(0, maxCutDB))
        r.boostCoef = Float(1 - exp(-block / (speed.windowSeconds * 1.5)))
        r.cutCoef = Float(1 - exp(-block / (speed.windowSeconds * 0.5)))
        return r
    }
}

public struct RealtimeLeveler: Sendable {
    public var shelf = BiquadCoefficients.identity
    public var highPass = BiquadCoefficients.identity
    public var powerCoef: Float = 0.00001
    public var target: Float = -16, maxBoost: Float = 6, maxCut: Float = 12
    public var boostCoef: Float = 0.001, cutCoef: Float = 0.004
    public init() {}
}

public final class LevelerStage {
    static let blockSize = 128
    static let gateLUFS: Float = -50       // below this it's silence/near-silence: hold the gain

    public var params = RealtimeLeveler()
    // K-weighting filter state: [channel][filter][z1, z2]
    private var kz = [Float](repeating: 0, count: 8)
    private var power: Float = 0
    private var gainDB: Float = 0, gainLin: Float = 1, gainStep: Float = 0
    private var counter = 0
    private var primed = false

    public init() {}

    /// Current levelling gain (dB) and measured loudness (LUFS).
    public var currentGainDB: Float { gainDB }
    public var loudnessLUFS: Float { -0.691 + 10 * log10f(max(power, 1e-12)) }

    @inline(__always)
    private func biquad(_ x: Float, _ c: BiquadCoefficients, _ i: Int) -> Float {
        let y = c.b0 * x + kz[i]
        kz[i] = c.b1 * x - c.a1 * y + kz[i + 1]
        kz[i + 1] = c.b2 * x - c.a2 * y
        return y
    }

    @inline(__always)
    public func process(_ l: inout Float, _ r: inout Float) {
        let p = params
        let kl = biquad(biquad(l, p.shelf, 0), p.highPass, 2)
        let kr = biquad(biquad(r, p.shelf, 4), p.highPass, 6)
        let pw = kl * kl + kr * kr             // BS.1770: sum of channel mean squares
        if !primed, pw > 1e-7 { power = pw; primed = true }
        power += (pw - power) * p.powerCoef

        if counter == 0 {
            let loud = loudnessLUFS
            if loud > Self.gateLUFS {
                let target = max(-p.maxCut, min(p.maxBoost, p.target - loud))
                gainDB += (target - gainDB) * (target < gainDB ? p.cutCoef : p.boostCoef)
            }
            let next = powf(10, gainDB / 20)
            gainStep = (next - gainLin) / Float(Self.blockSize)
        }
        counter = (counter + 1) % Self.blockSize
        gainLin += gainStep
        l *= gainLin
        r *= gainLin
    }
}

extension BiquadCoefficients {
    /// ITU-R BS.1770-4 K-weighting, stage 1 (head-related high shelf), for any sample rate.
    public static func kWeightingShelf(sampleRate fs: Double) -> BiquadCoefficients {
        let f0 = 1681.974450955533, g = 3.999843853973347, q = 0.7071752369554196
        let k = tan(Double.pi * f0 / fs)
        let vh = pow(10, g / 20), vb = pow(vh, 0.4996667741545416)
        let a0 = 1 + k / q + k * k
        return BiquadCoefficients(b0: Float((vh + vb * k / q + k * k) / a0), b1: Float(2 * (k * k - vh) / a0),
                                  b2: Float((vh - vb * k / q + k * k) / a0),
                                  a1: Float(2 * (k * k - 1) / a0), a2: Float((1 - k / q + k * k) / a0))
    }

    /// ITU-R BS.1770-4 K-weighting, stage 2 (RLB high-pass).
    public static func kWeightingHighPass(sampleRate fs: Double) -> BiquadCoefficients {
        let f0 = 38.13547087602444, q = 0.5003270373238773
        let k = tan(Double.pi * f0 / fs)
        let a0 = 1 + k / q + k * k
        return BiquadCoefficients(b0: 1, b1: -2, b2: 1, a1: Float(2 * (k * k - 1) / a0), a2: Float((1 - k / q + k * k) / a0))
    }

    /// RBJ 2nd-order high-pass.
    public static func highPass(_ f: Double, q: Double, sampleRate: Double) -> BiquadCoefficients {
        let w0 = 2 * Double.pi * min(f, sampleRate * 0.45) / sampleRate
        let cw = cos(w0), alpha = sin(w0) / (2 * q)
        let a0 = 1 + alpha
        return BiquadCoefficients(b0: Float((1 + cw) / 2 / a0), b1: Float(-(1 + cw) / a0), b2: Float((1 + cw) / 2 / a0),
                                  a1: Float(-2 * cw / a0), a2: Float((1 - alpha) / a0))
    }
}
