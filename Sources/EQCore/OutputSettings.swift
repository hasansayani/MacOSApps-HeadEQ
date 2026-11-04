/// Post-EQ output fine-tuning. Applied in this order:
/// swap → crossfeed → width/mono → balance → polarity → gain → limiter.
public struct OutputSettings: Codable, Equatable, Sendable {
    public var gainDB: Double = 0               // -12…+6 post-EQ trim
    public var balance: Double = 0              // -1 (left) … +1 (right)
    public var width: Double = 1                // 0 = mono, 1 = normal, 2 = extra wide
    public var mono = false
    public var swapChannels = false
    public var invertPolarity = false
    public var crossfeed: Double = 0            // 0 (off) … 1 (strong, ≈ -6 dB)
    public var crossfeedCutoff: Double = 700    // Hz
    public var limiterEnabled = true
    public var limiterCeilingDB: Double = -0.5  // -6…0 dBFS
    public var limiterReleaseMS: Double = 120

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = OutputSettings()
        gainDB = try c.decodeIfPresent(Double.self, forKey: .gainDB) ?? d.gainDB
        balance = try c.decodeIfPresent(Double.self, forKey: .balance) ?? d.balance
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? d.width
        mono = try c.decodeIfPresent(Bool.self, forKey: .mono) ?? d.mono
        swapChannels = try c.decodeIfPresent(Bool.self, forKey: .swapChannels) ?? d.swapChannels
        invertPolarity = try c.decodeIfPresent(Bool.self, forKey: .invertPolarity) ?? d.invertPolarity
        crossfeed = try c.decodeIfPresent(Double.self, forKey: .crossfeed) ?? d.crossfeed
        crossfeedCutoff = try c.decodeIfPresent(Double.self, forKey: .crossfeedCutoff) ?? d.crossfeedCutoff
        limiterEnabled = try c.decodeIfPresent(Bool.self, forKey: .limiterEnabled) ?? d.limiterEnabled
        limiterCeilingDB = try c.decodeIfPresent(Double.self, forKey: .limiterCeilingDB) ?? d.limiterCeilingDB
        limiterReleaseMS = try c.decodeIfPresent(Double.self, forKey: .limiterReleaseMS) ?? d.limiterReleaseMS
    }

    /// Plain-float snapshot for the real-time thread.
    public func realtime(sampleRate: Double) -> RealtimeOutput {
        RealtimeOutput(
            gain: Float(pow(10, gainDB / 20)),
            balance: Float(max(-1, min(1, balance))),
            width: mono ? 0 : Float(max(0, min(2, width))),
            swap: swapChannels,
            polarity: invertPolarity ? -1 : 1,
            crossfeed: Float(max(0, min(1, crossfeed)) * 0.5),
            crossfeedCoef: Float(1 - exp(-2 * Double.pi * crossfeedCutoff / sampleRate)),
            limiter: limiterEnabled,
            ceiling: Float(pow(10, min(0, limiterCeilingDB) / 20)),
            release: Float(1 - exp(-1 / (max(10, limiterReleaseMS) / 1000 * sampleRate))))
    }
}

public struct RealtimeOutput: Sendable {
    public var gain: Float = 1, balance: Float = 0, width: Float = 1
    public var swap = false, polarity: Float = 1
    public var crossfeed: Float = 0, crossfeedCoef: Float = 0.1
    public var limiter = true, ceiling: Float = 0.944, release: Float = 0.0002

    public init() {}
    public init(gain: Float, balance: Float, width: Float, swap: Bool, polarity: Float, crossfeed: Float,
                crossfeedCoef: Float, limiter: Bool, ceiling: Float, release: Float) {
        self.gain = gain; self.balance = balance; self.width = width; self.swap = swap; self.polarity = polarity
        self.crossfeed = crossfeed; self.crossfeedCoef = crossfeedCoef; self.limiter = limiter
        self.ceiling = ceiling; self.release = release
    }
}
