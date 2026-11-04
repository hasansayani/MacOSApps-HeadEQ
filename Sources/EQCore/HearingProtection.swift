/// Hearing protection designed to be inaudible in normal listening:
///
/// • Sudden-spike guard — compares short-term level (≈40 ms) with the recent
///   average (≈4 s). Only abrupt jumps well above what you were just hearing
///   (a loud ad, a notification, a mis-mastered track) are ridden down, then
///   released gradually as the new level becomes the norm. Musical dynamics
///   inside a song (a drop, a snare hit) are far below the threshold.
/// • Loudness cap — a slow, broadband volume ride on *sustained* level only.
///   No compression of transients, no EQ change, so tone is untouched.
/// • Exposure meter — estimates daily noise dose (NIOSH: 85 dB for 8 h,
///   3 dB exchange rate) from the output level, device volume and headphone
///   sensitivity. It's an estimate: calibrate sensitivity for accuracy.

public struct HearingProtectionSettings: Codable, Equatable, Sendable {
    public var enabled = true
    public var spikeGuard = true
    public var spikeThresholdDB: Double = 10      // jump above recent level that counts as a spike
    public var levelCap = true
    public var maxLevelSPL: Double = 90           // estimated dB SPL ceiling for sustained level
    /// Estimated dB SPL produced by a 0 dBFS RMS signal at full device volume.
    /// Typical headphones: 95–110. Lower = assumes quieter headphones.
    public var sensitivitySPL: Double = 100
    public var doseWarnings = true
    /// When today's dose reaches 100 %, lower the cap by this much (0 = off).
    public var overDoseCapReductionDB: Double = 5

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = HearingProtectionSettings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        spikeGuard = try c.decodeIfPresent(Bool.self, forKey: .spikeGuard) ?? d.spikeGuard
        spikeThresholdDB = try c.decodeIfPresent(Double.self, forKey: .spikeThresholdDB) ?? d.spikeThresholdDB
        levelCap = try c.decodeIfPresent(Bool.self, forKey: .levelCap) ?? d.levelCap
        maxLevelSPL = try c.decodeIfPresent(Double.self, forKey: .maxLevelSPL) ?? d.maxLevelSPL
        sensitivitySPL = try c.decodeIfPresent(Double.self, forKey: .sensitivitySPL) ?? d.sensitivitySPL
        doseWarnings = try c.decodeIfPresent(Bool.self, forKey: .doseWarnings) ?? d.doseWarnings
        overDoseCapReductionDB = try c.decodeIfPresent(Double.self, forKey: .overDoseCapReductionDB) ?? d.overDoseCapReductionDB
    }

    /// Digital (dBFS) ceiling equivalent to `maxLevelSPL` at the current device volume.
    public func capDBFS(deviceVolumeDB: Double, doseFraction: Double) -> Double {
        let reduction = doseFraction >= 1 ? overDoseCapReductionDB : 0
        return maxLevelSPL - reduction - sensitivitySPL - deviceVolumeDB
    }

    public func estimatedSPL(levelDBFS: Double, deviceVolumeDB: Double) -> Double {
        levelDBFS + sensitivitySPL + deviceVolumeDB
    }

    public func realtime(sampleRate: Double, capDBFS: Double) -> RealtimeHearing {
        func coef(_ seconds: Double) -> Float { Float(1 - exp(-1 / (seconds * sampleRate))) }
        let blockSeconds = Double(RealtimeHearing.blockSize) / sampleRate
        func blockCoef(_ seconds: Double) -> Float { Float(1 - exp(-blockSeconds / seconds)) }
        return RealtimeHearing(
            enabled: enabled && (spikeGuard || levelCap),
            spike: spikeGuard, spikeDB: Float(spikeThresholdDB),
            cap: levelCap, capDBFS: Float(capDBFS),
            shortCoef: coef(0.04), longCoef: coef(4), meterCoef: coef(1),
            spikeAttack: blockCoef(0.01), capAttack: blockCoef(1.5), release: blockCoef(2.0))
    }
}

public struct RealtimeHearing: Sendable {
    public static let blockSize = 128
    public var enabled = false
    public var spike = true, spikeDB: Float = 10
    public var cap = true, capDBFS: Float = 0
    public var shortCoef: Float = 0.0005, longCoef: Float = 0.000005, meterCoef: Float = 0.00002
    public var spikeAttack: Float = 0.9, capAttack: Float = 0.002, release: Float = 0.0013

    public init() {}
    public init(enabled: Bool, spike: Bool, spikeDB: Float, cap: Bool, capDBFS: Float, shortCoef: Float,
                longCoef: Float, meterCoef: Float, spikeAttack: Float, capAttack: Float, release: Float) {
        self.enabled = enabled; self.spike = spike; self.spikeDB = spikeDB; self.cap = cap; self.capDBFS = capDBFS
        self.shortCoef = shortCoef; self.longCoef = longCoef; self.meterCoef = meterCoef
        self.spikeAttack = spikeAttack; self.capAttack = capAttack; self.release = release
    }
}

/// Real-time level guard. Allocation-free; used inside `EQProcessor`.
public struct HearingGuard {
    var params = RealtimeHearing()
    var shortPow: Float = 0, longPow: Float = 0, meterPow: Float = 0
    var gainDB: Float = 0
    var gainLin: Float = 1, gainStep: Float = 0
    var counter = 0
    // Onset handling: when audio starts after silence (play after pause, new
    // app), the first ~300 ms *defines* the reference level instead of being
    // judged against silence — so pressing play never sounds ducked.
    var silentBlocks = Int.max / 2
    var onsetBlocks = 0

    /// Current gain reduction (dB, ≤ 0) and post-guard output level (dBFS RMS, ~1 s).
    public var reductionDB: Float { gainDB }
    public var outputLevelDBFS: Float { 10 * log10f(max(meterPow, 1e-12)) }

    @inline(__always)
    mutating func process(_ l: inout Float, _ r: inout Float) {
        let p = params
        let power = (l * l + r * r) * 0.5
        if p.enabled {
            shortPow += (power - shortPow) * p.shortCoef
            longPow += (power - longPow) * p.longCoef
            if counter == 0 { recompute() }
            counter = (counter + 1) % RealtimeHearing.blockSize
            gainLin += gainStep
            l *= gainLin; r *= gainLin
        }
        let outPow = p.enabled ? power * gainLin * gainLin : power
        meterPow += (outPow - meterPow) * p.meterCoef
    }

    private mutating func recompute() {
        let p = params
        let shortDB = 10 * log10f(max(shortPow, 1e-12))
        if shortDB < -50 {
            silentBlocks += 1
        } else {
            if silentBlocks > 180 { onsetBlocks = 110 }      // ≥ 0.5 s silence → 300 ms onset window
            silentBlocks = 0
        }
        if onsetBlocks > 0 {
            longPow = max(longPow, shortPow)
            onsetBlocks -= 1
        }
        let longDB = 10 * log10f(max(longPow, 1e-12))
        var spikeTarget: Float = 0, capTarget: Float = 0
        if p.spike, shortDB > -45, shortDB > longDB + p.spikeDB {
            spikeTarget = longDB + p.spikeDB - shortDB
        }
        if p.cap, longDB > p.capDBFS { capTarget = p.capDBFS - longDB }
        let target = min(spikeTarget, capTarget, 0)
        if target < gainDB {
            gainDB += (target - gainDB) * (spikeTarget <= capTarget ? p.spikeAttack : p.capAttack)
        } else {
            gainDB += (target - gainDB) * p.release
        }
        let next = powf(10, gainDB / 20)
        gainStep = (next - gainLin) / Float(RealtimeHearing.blockSize)
    }
}

/// Daily noise-dose accumulator (NIOSH REL: 85 dBA for 8 h, 3 dB exchange rate).
public struct ExposureMeter: Codable, Equatable, Sendable {
    public var day: Int            // caller-defined day number (e.g. days since 1970, local time)
    public var dose: Double = 0    // 1.0 = 100 % of the daily allowance
    public var listeningSeconds: Double = 0
    public var peakSPL: Double = 0

    public init(day: Int) { self.day = day }

    public static func allowedSeconds(atSPL spl: Double) -> Double {
        8 * 3600 / pow(2, (spl - 85) / 3)
    }

    /// Add `seconds` of listening at an estimated level. Silence (< 40 dB) is ignored.
    public mutating func add(spl: Double, seconds: Double) {
        guard spl >= 40, seconds > 0 else { return }
        listeningSeconds += seconds
        peakSPL = max(peakSPL, spl)
        dose += seconds / Self.allowedSeconds(atSPL: spl)
    }

    /// Time left at `spl` before reaching 100 % (nil if already over).
    public func remainingSeconds(atSPL spl: Double) -> Double? {
        dose >= 1 ? nil : (1 - dose) * Self.allowedSeconds(atSPL: spl)
    }
}
