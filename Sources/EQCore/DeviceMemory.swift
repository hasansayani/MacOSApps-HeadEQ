/// Per-device memory: each output device (headphones, DAC, speakers) keeps
/// its own headphone profile, music curve and output settings, restored
/// automatically when that device becomes active.

public struct DeviceSnapshot: Codable, Equatable, Sendable {
    public var deviceName: String
    public var headphoneProfileID: String
    public var musicPresetID: String
    public var bandGains: [Double]
    public var graphicQ: Double
    public var preampDB: Double
    public var autoPreamp: Bool
    public var output: OutputSettings

    public init(deviceName: String, settings s: EQSettings) {
        self.deviceName = deviceName
        headphoneProfileID = s.headphoneProfileID
        musicPresetID = s.musicPresetID
        bandGains = s.bandGains
        graphicQ = s.graphicQ
        preampDB = s.preampDB
        autoPreamp = s.autoPreamp
        output = s.output
    }

    /// Apply this snapshot on top of `settings` (global options are kept).
    public func applied(to settings: EQSettings) -> EQSettings {
        var s = settings
        s.headphoneProfileID = headphoneProfileID
        s.musicPresetID = musicPresetID
        if bandGains.count == GraphicEQ.frequencies.count { s.bandGains = bandGains }
        s.graphicQ = graphicQ
        s.preampDB = preampDB
        s.autoPreamp = autoPreamp
        s.output = output
        return s
    }
}

public struct DeviceMemory: Codable, Equatable, Sendable {
    public private(set) var snapshots: [String: DeviceSnapshot] = [:]   // keyed by device UID

    public init() {}

    public mutating func remember(_ settings: EQSettings, deviceUID: String, deviceName: String) {
        snapshots[deviceUID] = DeviceSnapshot(deviceName: deviceName, settings: settings)
    }

    public func snapshot(for deviceUID: String) -> DeviceSnapshot? { snapshots[deviceUID] }

    public mutating func forget(_ deviceUID: String) { snapshots[deviceUID] = nil }

    /// Switching devices: save the outgoing device's state, return the settings for the incoming one
    /// (its snapshot if known, otherwise the current settings unchanged).
    public mutating func switching(from old: (uid: String, name: String)?, to newUID: String, current: EQSettings) -> EQSettings {
        if let old { remember(current, deviceUID: old.uid, deviceName: old.name) }
        return snapshots[newUID]?.applied(to: current) ?? current
    }
}
