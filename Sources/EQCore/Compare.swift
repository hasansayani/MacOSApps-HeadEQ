/// A/B and blind comparison. Two "slots" capture a complete sound setup
/// (headphone profile, curve, preamp, output stage). Switching is instant and
/// can be level-matched, because louder almost always sounds "better".

public typealias SoundSnapshot = DeviceSnapshot

public enum ABSlot: String, Codable, Sendable, CaseIterable { case a = "A", b = "B" }

extension SoundSnapshot {
    /// Average gain of the full chain over 100 Hz – 10 kHz (dB): what loudness matching compensates for.
    public func averageGainDB(headphone: HeadphoneProfile, base: EQSettings) -> Double {
        let s = applied(to: base)
        let filters = s.filters(headphone: headphone)
        let freqs = FrequencyResponse.logFrequencies(count: 60, from: 100, to: 10_000)
        let curve = FrequencyResponse.curve(filters: filters, preamp: s.effectivePreamp(filters: filters), frequencies: freqs)
        return curve.reduce(0, +) / Double(curve.count) + s.output.gainDB
    }
}

/// Small deterministic RNG so tests are reproducible (SplitMix64).
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Blind preference test: each trial hides A and B behind "1" and "2" in random order.
public struct BlindTestSession: Sendable {
    public let trials: Int
    public private(set) var assignments: [ABSlot] = []   // which slot "1" is, per trial
    public private(set) var picks: [ABSlot] = []         // which slot was preferred, per trial

    public init<R: RandomNumberGenerator>(trials: Int = 10, rng: inout R) {
        self.trials = max(1, trials)
        assignments = (0..<self.trials).map { _ in Bool.random(using: &rng) ? .a : .b }
    }

    public init(trials: Int = 10) {
        var g = SystemRandomNumberGenerator()
        self.init(trials: trials, rng: &g)
    }

    public var trialIndex: Int { picks.count }
    public var isFinished: Bool { picks.count >= trials }

    /// The slot behind option 1 or 2 in the current trial.
    public func slot(forOption option: Int) -> ABSlot? {
        guard !isFinished else { return nil }
        let one = assignments[trialIndex]
        return option == 1 ? one : (one == .a ? .b : .a)
    }

    public mutating func choose(option: Int) {
        guard let s = slot(forOption: option) else { return }
        picks.append(s)
    }

    public var countA: Int { picks.filter { $0 == .a }.count }
    public var countB: Int { picks.filter { $0 == .b }.count }

    /// Two-sided binomial p-value against "no real preference" (p = 0.5).
    public var pValue: Double { Self.binomialTwoSided(k: max(countA, countB), n: picks.count) }

    public var verdict: String {
        guard isFinished else { return "In progress" }
        if pValue < 0.05 {
            return "You reliably prefer \(countA > countB ? "A" : "B") (\(max(countA, countB)) of \(trials), p = \(Self.format(pValue)))."
        }
        return "No reliable preference (\(countA)–\(countB), p = \(Self.format(pValue))). The difference may be too small to hear."
    }

    static func format(_ p: Double) -> String {
        let r = (p * 1000).rounded() / 1000
        return r < 0.001 ? "< 0.001" : String(r)
    }

    public static func binomialTwoSided(k: Int, n: Int) -> Double {
        guard n > 0 else { return 1 }
        func choose(_ n: Int, _ k: Int) -> Double {
            var r = 1.0
            for i in 0..<k { r = r * Double(n - i) / Double(i + 1) }
            return r
        }
        let kk = max(k, n - k)
        var tail = 0.0
        for i in kk...n { tail += choose(n, i) }
        return min(1, 2 * tail / pow(2, Double(n)))
    }
}
