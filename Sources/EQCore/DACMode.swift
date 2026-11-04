/// DAC mode: bit-perfect bypass when nothing would change the sound, and a
/// remembered hardware sample rate per device.

public struct DACSettings: Codable, Equatable, Sendable {
    public var enabled = false
    /// Stop processing entirely (audio goes straight to the device) when the chain is neutral.
    public var bypassWhenNeutral = true
    /// Apply the remembered sample rate when a device becomes active.
    public var applyPreferredRate = true
    public var preferredRates: [String: Double] = [:]    // device UID → Hz

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DACSettings()
        enabled = c.value(.enabled, d.enabled)
        bypassWhenNeutral = c.value(.bypassWhenNeutral, d.bypassWhenNeutral)
        applyPreferredRate = c.value(.applyPreferredRate, d.applyPreferredRate)
        preferredRates = c.value(.preferredRates, d.preferredRates)
    }
}

extension EQSettings {
    /// Why the chain would alter the audio (empty = neutral → bit-perfect bypass possible).
    public func nonNeutralReasons(headphone: HeadphoneProfile) -> [String] {
        var r: [String] = []
        if headphone.filters.contains(where: { abs($0.gain) >= 0.05 }) { r.append("Headphone correction “\(headphone.name)”") }
        if bandGains.contains(where: { abs($0) >= 0.05 }) { r.append("Graphic EQ isn't flat") }
        if abs(effectivePreamp(filters: filters(headphone: headphone))) >= 0.05 { r.append("Preamp") }
        let o = output, d = OutputSettings()
        if abs(o.gainDB) >= 0.05 { r.append("Output gain") }
        if abs(o.balance) >= 0.005 { r.append("Balance") }
        if o.mono || abs(o.width - 1) >= 0.005 { r.append("Stereo width / mono") }
        if o.swapChannels { r.append("L/R swap") }
        if o.invertPolarity { r.append("Polarity invert") }
        if o.crossfeed >= 0.005 { r.append("Crossfeed") }
        if o.limiterEnabled && o.limiterCeilingDB < d.limiterCeilingDB - 0.05 { r.append("Limiter ceiling below default") }
        if hearing.enabled && (hearing.spikeGuard || hearing.levelCap) { r.append("Hearing protection") }
        if features.surround.enabled { r.append("Virtual surround") }
        if features.leveler.enabled { r.append("Volume levelling") }
        if features.personal.enabled && features.personal.audiogram != nil { r.append("Personal hearing correction") }
        return r
    }

    public func isNeutral(headphone: HeadphoneProfile) -> Bool { nonNeutralReasons(headphone: headphone).isEmpty }

    /// Whether DAC mode should bypass processing right now.
    public func shouldBypass(headphone: HeadphoneProfile) -> Bool {
        features.dac.enabled && features.dac.bypassWhenNeutral && isNeutral(headphone: headphone)
    }
}

public struct PhysicalFormat: Equatable, Sendable {
    public var sampleRate: Double
    public var bitsPerChannel: Int
    public var channels: Int
    public var isFloat: Bool
    public init(sampleRate: Double, bitsPerChannel: Int, channels: Int, isFloat: Bool) {
        self.sampleRate = sampleRate; self.bitsPerChannel = bitsPerChannel; self.channels = channels; self.isFloat = isFloat
    }
    public var description: String {
        "\(bitsPerChannel)-bit\(isFloat ? " float" : "") · \(sampleRate.truncatingRemainder(dividingBy: 1000) == 0 ? String(Int(sampleRate / 1000)) : String(sampleRate / 1000)) kHz · \(channels) ch"
    }
}
