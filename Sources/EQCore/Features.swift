/// Optional features. Every feature has an on/off switch; when off, its DSP
/// stage is never allocated and its background work never scheduled, so it
/// costs no CPU or memory.

public struct FeatureSettings: Codable, Equatable, Sendable {
    /// Use measured AutoEQ corrections for built-in headphone models.
    public var measuredProfiles = true
    /// Remember settings per output device and restore them on reconnect.
    public var deviceMemory = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FeatureSettings()
        measuredProfiles = c.value(.measuredProfiles, d.measuredProfiles)
        deviceMemory = c.value(.deviceMemory, d.deviceMemory)
    }

    /// Catalogue of optional features, in display order.
    public static let catalogue: [FeatureInfo] = [
        FeatureInfo(id: "measured", title: "Measured headphone profiles",
                    summary: "Built-in models use real AutoEQ measurements (oratory1990, Rtings…) instead of HeadEQ's approximations.",
                    cost: "No runtime cost", icon: "ruler"),
        FeatureInfo(id: "deviceMemory", title: "Per-device memory",
                    summary: "Each headphone, DAC or speaker remembers its own profile, preset and output settings, restored automatically when it connects.",
                    cost: "No audio cost · a few KB of settings", icon: "memorychip"),
    ]

    /// Generic on/off access by feature id (used by the Features page).
    public subscript(isOn id: String) -> Bool {
        get { isOnStorage(id) }
        set { setOnStorage(id, newValue) }
    }

    func isOnStorage(_ id: String) -> Bool {
        switch id {
        case "measured": return measuredProfiles
        case "deviceMemory": return deviceMemory
        default: return false
        }
    }

    mutating func setOnStorage(_ id: String, _ on: Bool) {
        switch id {
        case "measured": measuredProfiles = on
        case "deviceMemory": deviceMemory = on
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
