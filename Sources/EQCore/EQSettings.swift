/// The complete user-facing EQ state, serializable (Codable) so it can be
/// shared across platforms or synced between devices.
public struct EQSettings: Codable, Equatable, Sendable {
    public var enabled = true
    public var headphoneProfileID = HeadphoneProfile.none.id
    public var autoDetectHeadphones = true
    public var musicPresetID = MusicPreset.flat.id
    public var bandGains: [Double] = MusicPreset.flat.gains
    public var preampDB: Double = 0
    public var autoPreamp = true
    /// Persistent device UID chosen by the user; nil follows the system default.
    public var outputDeviceUID: String? = nil
    /// Bandwidth of the graphic EQ bands (higher = narrower).
    public var graphicQ: Double = GraphicEQ.q
    public var output = OutputSettings()
    public var hearing = HearingProtectionSettings()

    public init() {}

    // Tolerant decoding: settings saved by older versions (or other platforms)
    // keep working when fields are added.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = EQSettings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        headphoneProfileID = try c.decodeIfPresent(String.self, forKey: .headphoneProfileID) ?? d.headphoneProfileID
        autoDetectHeadphones = try c.decodeIfPresent(Bool.self, forKey: .autoDetectHeadphones) ?? d.autoDetectHeadphones
        musicPresetID = try c.decodeIfPresent(String.self, forKey: .musicPresetID) ?? d.musicPresetID
        bandGains = try c.decodeIfPresent([Double].self, forKey: .bandGains) ?? d.bandGains
        if bandGains.count != GraphicEQ.frequencies.count { bandGains = d.bandGains }
        preampDB = try c.decodeIfPresent(Double.self, forKey: .preampDB) ?? d.preampDB
        autoPreamp = try c.decodeIfPresent(Bool.self, forKey: .autoPreamp) ?? d.autoPreamp
        outputDeviceUID = try c.decodeIfPresent(String.self, forKey: .outputDeviceUID)
        graphicQ = try c.decodeIfPresent(Double.self, forKey: .graphicQ) ?? d.graphicQ
        output = try c.decodeIfPresent(OutputSettings.self, forKey: .output) ?? d.output
        hearing = try c.decodeIfPresent(HearingProtectionSettings.self, forKey: .hearing) ?? d.hearing
    }

    /// The full filter chain: headphone correction followed by the graphic EQ.
    public func filters(headphone: HeadphoneProfile) -> [FilterSpec] {
        Array(headphone.filters.prefix(HeadphoneProfile.maxFilters)) + GraphicEQ.filters(gains: bandGains, q: graphicQ)
    }

    /// Preamp actually applied (auto mode prevents digital clipping).
    public func effectivePreamp(filters: [FilterSpec]) -> Double {
        guard autoPreamp else { return preampDB }
        return -max(0, FrequencyResponse.peakGain(filters: filters))
    }
}
