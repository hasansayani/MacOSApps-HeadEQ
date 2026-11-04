/// Built-in hearing test + personal correction.
///
/// The test is a simplified Hughson-Westlake staircase per ear and frequency
/// (down 10 dB when heard, up 5 dB when not; threshold = lowest level heard
/// on two ascending runs). Levels are digital (dBFS) because consumer
/// headphones aren't calibrated, so the correction uses each threshold
/// *relative to your best one* and applies a fraction of the difference
/// (like the classic half-gain rule). This is not a medical hearing test.

public enum Ear: String, Codable, Sendable, CaseIterable {
    case left, right
    public var title: String { self == .left ? "Left" : "Right" }
}

public struct AudiogramPoint: Codable, Equatable, Sendable {
    public var frequency: Double
    public var thresholdDBFS: Double
    public init(frequency: Double, thresholdDBFS: Double) { self.frequency = frequency; self.thresholdDBFS = thresholdDBFS }
}

public struct Audiogram: Codable, Equatable, Sendable {
    public var left: [AudiogramPoint] = []
    public var right: [AudiogramPoint] = []
    public var takenOn: String = ""      // ISO date, set by the platform layer

    public init(left: [AudiogramPoint] = [], right: [AudiogramPoint] = []) { self.left = left; self.right = right }

    public func points(_ ear: Ear) -> [AudiogramPoint] { (ear == .left ? left : right).sorted { $0.frequency < $1.frequency } }

    /// Best (lowest) threshold across both ears — the reference for "normal" on these headphones.
    public var reference: Double? { (left + right).map(\.thresholdDBFS).min() }

    /// Relative loss (dB above the reference) per frequency.
    public func relativeLoss(_ ear: Ear) -> [(frequency: Double, loss: Double)] {
        guard let ref = reference else { return [] }
        return points(ear).map { ($0.frequency, max(0, $0.thresholdDBFS - ref)) }
    }

    /// Correction filters for one ear: peaking boosts at the tested frequencies.
    public func correction(_ ear: Ear, strength: Double, maxBoostDB: Double) -> [FilterSpec] {
        relativeLoss(ear).compactMap { f, loss in
            let g = min(maxBoostDB, loss * max(0, min(1, strength)))
            return g >= 0.5 ? FilterSpec.peak(f, (g * 10).rounded() / 10, q: 1.4) : nil
        }
    }
}

public struct PersonalCorrectionSettings: Codable, Equatable, Sendable {
    public var enabled = false
    public var strength: Double = 0.5        // fraction of the relative loss to restore (half-gain rule)
    public var maxBoostDB: Double = 10
    public var audiogram: Audiogram?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PersonalCorrectionSettings()
        enabled = c.value(.enabled, d.enabled)
        strength = c.value(.strength, d.strength)
        maxBoostDB = c.value(.maxBoostDB, d.maxBoostDB)
        audiogram = try? c.decodeIfPresent(Audiogram.self, forKey: .audiogram)
    }

    public func filters(_ ear: Ear) -> [FilterSpec] {
        audiogram?.correction(ear, strength: strength, maxBoostDB: maxBoostDB) ?? []
    }

    public func realtime(sampleRate: Double) -> RealtimePersonal {
        var r = RealtimePersonal()
        let lf = filters(.left), rf = filters(.right)
        for (i, f) in lf.prefix(Biquad8.capacity).enumerated() { r.left[i] = BiquadCoefficients(f, sampleRate: sampleRate) }
        for (i, f) in rf.prefix(Biquad8.capacity).enumerated() { r.right[i] = BiquadCoefficients(f, sampleRate: sampleRate) }
        r.left.count = min(lf.count, Biquad8.capacity)
        r.right.count = min(rf.count, Biquad8.capacity)
        // Keep it clip-safe: pre-attenuate by the larger of the two ears' peak boost.
        let peak = max(FrequencyResponse.peakGain(filters: lf, sampleRate: sampleRate),
                       FrequencyResponse.peakGain(filters: rf, sampleRate: sampleRate), 0)
        r.preamp = Float(pow(10, -peak / 20))
        return r
    }
}

/// Eight biquad coefficient slots stored inline (no heap) for the audio thread.
public struct Biquad8: Sendable {
    public static let capacity = 8
    public var count = 0
    private var c0 = BiquadCoefficients.identity, c1 = BiquadCoefficients.identity, c2 = BiquadCoefficients.identity,
                c3 = BiquadCoefficients.identity, c4 = BiquadCoefficients.identity, c5 = BiquadCoefficients.identity,
                c6 = BiquadCoefficients.identity, c7 = BiquadCoefficients.identity
    public init() {}
    public subscript(i: Int) -> BiquadCoefficients {
        get {
            switch i { case 0: return c0; case 1: return c1; case 2: return c2; case 3: return c3
            case 4: return c4; case 5: return c5; case 6: return c6; default: return c7 }
        }
        set {
            switch i { case 0: c0 = newValue; case 1: c1 = newValue; case 2: c2 = newValue; case 3: c3 = newValue
            case 4: c4 = newValue; case 5: c5 = newValue; case 6: c6 = newValue; default: c7 = newValue }
        }
    }
}

public struct RealtimePersonal: Sendable {
    public var left = Biquad8(), right = Biquad8()
    public var preamp: Float = 1
    public init() {}
}

/// Per-ear correction stage.
public final class PersonalEQStage {
    public var params = RealtimePersonal()
    private var zl = [Float](repeating: 0, count: Biquad8.capacity * 2)
    private var zr = [Float](repeating: 0, count: Biquad8.capacity * 2)
    public init() {}

    @inline(__always)
    private static func run(_ x: Float, _ f: Biquad8, _ z: inout [Float]) -> Float {
        var x = x
        for i in 0..<f.count {
            let c = f[i]
            let y = c.b0 * x + z[2 * i]
            z[2 * i] = c.b1 * x - c.a1 * y + z[2 * i + 1]
            z[2 * i + 1] = c.b2 * x - c.a2 * y
            x = y
        }
        return x
    }

    @inline(__always)
    public func process(_ l: inout Float, _ r: inout Float) {
        let p = params
        l = Self.run(l * p.preamp, p.left, &zl)
        r = Self.run(r * p.preamp, p.right, &zr)
    }
}

/// The test procedure (pure logic — the platform plays the tones).
public struct HearingTestSession: Sendable {
    public struct Presentation: Equatable, Sendable {
        public var ear: Ear
        public var frequency: Double
        public var levelDBFS: Double
    }

    public static let frequencies: [Double] = [1000, 2000, 4000, 6000, 8000, 500, 250]
    public static let startLevel = -40.0
    public static let minLevel = -100.0
    public static let maxLevel = -10.0

    public let ears: [Ear]
    private var queue: [(Ear, Double)]
    private var level = startLevel
    private var lastWasHeard: Bool?
    private var ascendingHits: [Double: Int] = [:]
    private var presentations = 0
    private var lowestHeard: Double?
    private var results: [Ear: [AudiogramPoint]] = [:]
    private let totalSteps: Int

    public init(ears: [Ear] = [.left, .right]) {
        self.ears = ears
        queue = ears.flatMap { e in Self.frequencies.map { (e, $0) } }
        totalSteps = queue.count
    }

    public var current: Presentation? {
        queue.first.map { Presentation(ear: $0.0, frequency: $0.1, levelDBFS: level) }
    }

    public var isFinished: Bool { queue.isEmpty }
    public var progress: Double { totalSteps == 0 ? 1 : Double(totalSteps - queue.count) / Double(totalSteps) }

    public mutating func respond(heard: Bool) {
        guard !queue.isEmpty else { return }
        presentations += 1
        if heard {
            lowestHeard = min(lowestHeard ?? level, level)
            // A "hit" on an ascending run: previous response was "not heard".
            if lastWasHeard == false {
                ascendingHits[level, default: 0] += 1
                if ascendingHits[level]! >= 2 { finish(threshold: level); return }
            }
            if level <= Self.minLevel { finish(threshold: Self.minLevel); return }
            level = max(Self.minLevel, level - 10)
        } else {
            if level >= Self.maxLevel { finish(threshold: Self.maxLevel); return }
            level = min(Self.maxLevel, level + 5)
        }
        lastWasHeard = heard
        if presentations >= 14 { finish(threshold: lowestHeard ?? Self.maxLevel) }
    }

    private mutating func finish(threshold: Double) {
        let (ear, f) = queue.removeFirst()
        results[ear, default: []].append(AudiogramPoint(frequency: f, thresholdDBFS: threshold))
        level = Self.startLevel
        lastWasHeard = nil
        ascendingHits = [:]
        presentations = 0
        lowestHeard = nil
    }

    public var audiogram: Audiogram { Audiogram(left: results[.left] ?? [], right: results[.right] ?? []) }
}
