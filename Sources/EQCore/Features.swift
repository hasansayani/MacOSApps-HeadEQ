/// Optional features. Every feature has an on/off switch; when off, its DSP
/// stage is never allocated and its background work never scheduled, so it
/// costs no CPU or memory.

public struct FeatureSettings: Codable, Equatable, Sendable {
    /// Use measured AutoEQ corrections for built-in headphone models.
    public var measuredProfiles = true
    /// Remember settings per output device and restore them on reconnect.
    public var deviceMemory = false
    public var surround = SurroundSettings()
    public var leveler = LevelerSettings()
    public var personal = PersonalCorrectionSettings()
    public var dac = DACSettings()
    /// A/B & blind comparison tools.
    public var compare = false
    /// Sync user presets & headphones through a folder (iCloud Drive by default).
    public var sync = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FeatureSettings()
        measuredProfiles = c.value(.measuredProfiles, d.measuredProfiles)
        deviceMemory = c.value(.deviceMemory, d.deviceMemory)
        surround = c.value(.surround, d.surround)
        leveler = c.value(.leveler, d.leveler)
        personal = c.value(.personal, d.personal)
        dac = c.value(.dac, d.dac)
        compare = c.value(.compare, d.compare)
        sync = c.value(.sync, d.sync)
    }

    /// Catalogue of optional features, in display order.
    public static let catalogue: [FeatureInfo] = [
        FeatureInfo(id: "measured", title: "Measured headphone profiles",
                    summary: "Built-in models use real AutoEQ measurements (oratory1990, Rtings…) instead of HeadEQ's approximations.",
                    cost: "No runtime cost", icon: "ruler"),
        FeatureInfo(id: "deviceMemory", title: "Per-device memory",
                    summary: "Each headphone, DAC or speaker remembers its own profile, preset and output settings, restored automatically when it connects.",
                    cost: "No audio cost · a few KB of settings", icon: "memorychip"),
        FeatureInfo(id: "surround", title: "Virtual surround",
                    summary: "Hear headphones like a pair of speakers in front of you: natural crossfeed with head-shadow timing plus early room reflections.",
                    cost: "≈ 70 KB buffers · light per-sample work", icon: "person.wave.2"),
        FeatureInfo(id: "leveler", title: "Volume levelling",
                    summary: "Evens out loudness between songs, apps and videos with a slow, transparent gain ride measured in LUFS (ITU BS.1770).",
                    cost: "< 1 KB · 4 filters per sample", icon: "speaker.wave.2.bubble"),
        FeatureInfo(id: "personal", title: "Hearing test & personal correction",
                    summary: "A short tone test per ear builds a gentle correction for the frequencies you hear less well, applied separately to each ear.",
                    cost: "< 1 KB · up to 16 filters per sample", icon: "waveform.and.person.filled"),
        FeatureInfo(id: "dac", title: "DAC mode",
                    summary: "Bit-perfect bypass when nothing would change the sound, a remembered hardware sample rate per device, and the real device format.",
                    cost: "Saves CPU — bypass stops processing entirely", icon: "cable.connector"),
        FeatureInfo(id: "compare", title: "A/B & blind comparison",
                    summary: "Capture two setups and switch instantly with level matching, or run a blind preference test with a significance check.",
                    cost: "No runtime cost", icon: "arrow.left.arrow.right.square"),
        FeatureInfo(id: "sync", title: "Preset sync",
                    summary: "Keep your presets and headphone profiles in sync across Macs through iCloud Drive (or any synced folder such as Dropbox).",
                    cost: "Checks the sync file every 30 s while on", icon: "arrow.triangle.2.circlepath.icloud"),
    ]

    /// Processing stages to run for these settings.
    public var processing: ProcessingConfig {
        ProcessingConfig(surround: surround.enabled ? surround : nil,
                         leveler: leveler.enabled ? leveler : nil,
                         // Only allocate the per-ear stage once there's a test result to apply.
                         personal: personal.enabled && personal.audiogram != nil ? personal : nil)
    }

    /// Generic on/off access by feature id (used by the Features page).
    public subscript(isOn id: String) -> Bool {
        get { isOnStorage(id) }
        set { setOnStorage(id, newValue) }
    }

    func isOnStorage(_ id: String) -> Bool {
        switch id {
        case "measured": return measuredProfiles
        case "deviceMemory": return deviceMemory
        case "surround": return surround.enabled
        case "leveler": return leveler.enabled
        case "personal": return personal.enabled
        case "dac": return dac.enabled
        case "compare": return compare
        case "sync": return sync
        default: return false
        }
    }

    mutating func setOnStorage(_ id: String, _ on: Bool) {
        switch id {
        case "measured": measuredProfiles = on
        case "deviceMemory": deviceMemory = on
        case "surround": surround.enabled = on
        case "leveler": leveler.enabled = on
        case "personal": personal.enabled = on
        case "dac": dac.enabled = on
        case "compare": compare = on
        case "sync": sync = on
        default: break
        }
    }
}

/// Catalogue entry shown on the Features page.
public struct FeatureInfo: Identifiable, Sendable {
    public var id: String
    public var title: String
    public var summary: String
    /// What the feature costs when on (shown so people can trade features for battery/CPU).
    public var cost: String
    public var icon: String

    public init(id: String, title: String, summary: String, cost: String, icon: String) {
        self.id = id; self.title = title; self.summary = summary; self.cost = cost; self.icon = icon
    }
}

extension KeyedDecodingContainer {
    /// `decodeIfPresent` with a default — keeps settings from older versions decodable.
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
}
