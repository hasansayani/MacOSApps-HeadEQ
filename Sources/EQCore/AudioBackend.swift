/// Contract every platform audio backend implements. The UI/model layer only
/// talks to this protocol, so porting means writing a new backend:
///   macOS   – Core Audio process tap (system-wide)       [implemented]
///   iOS     – AVAudioEngine for in-app playback (iOS has no system-wide EQ)
///   Android – android.media.audiofx.DynamicsProcessing on session 0 / per app
///   Windows – WASAPI loopback + output, or an APO
///   Linux   – PipeWire filter-chain node

public enum DeviceTransport: String, Codable, Sendable {
    case builtIn = "Built-in", usb = "USB", bluetooth = "Bluetooth", hdmi = "HDMI",
         displayPort = "DisplayPort", thunderbolt = "Thunderbolt", airPlay = "AirPlay",
         virtual = "Virtual", aggregate = "Aggregate", unknown = "Other"
}

public struct OutputDevice: Identifiable, Hashable, Sendable {
    public var id: String { uid }
    public var uid: String
    public var name: String
    public var transport: DeviceTransport
    public var sampleRate: Double
    public var channels: Int

    public init(uid: String, name: String, transport: DeviceTransport, sampleRate: Double, channels: Int) {
        self.uid = uid; self.name = name; self.transport = transport
        self.sampleRate = sampleRate; self.channels = channels
    }

    /// Heuristic hook for upcoming external DAC support (USB/Thunderbolt
    /// interfaces). DAC features — sample-rate/bit-depth switching, bit-perfect
    /// bypass, hardware volume — will key off this.
    public var isLikelyExternalDAC: Bool {
        transport == .usb || transport == .thunderbolt
    }
}

public enum BackendStatus: Equatable, Sendable {
    case stopped
    case running(deviceName: String, sampleRate: Double)
    case failed(String)
}

public protocol AudioBackend: AnyObject {
    func outputDevices() -> [OutputDevice]
    func defaultOutputDevice() -> OutputDevice?
    /// Start processing system audio into `device`. Restarts if already running.
    func start(device: OutputDevice) throws
    func stop()
    /// Thread-safe; may be called any time while running.
    func update(filters: [FilterSpec], preampDB: Double)
    /// Thread-safe output-stage update (balance, width, crossfeed, limiter…).
    func update(output: OutputSettings)
    /// Hardware sample rates the device supports, and switching between them.
    func availableSampleRates(for device: OutputDevice) -> [Double]
    func setSampleRate(_ rate: Double, for device: OutputDevice) throws
    /// Newest processed output samples (mono mix) for visualizers.
    var visualizerRing: SampleRing { get }
    /// Current limiter gain reduction in dB (≤ 0), for metering.
    var limiterReductionDB: Float { get }
    /// Optional processing stages (nil members = feature off, nothing allocated).
    func update(processing: ProcessingConfig)
    /// Hearing protection: parameters, gain reduction and output level for metering.
    func update(hearing: RealtimeHearing)
    var protectionReductionDB: Float { get }
    var outputLevelDBFS: Float { get }
    /// Device output volume in dB relative to full scale (0 = max), if the device exposes it.
    func outputVolumeDB(for device: OutputDevice) -> Double?
    var sampleRate: Double { get }
    /// Called (on the main thread) when the device list or system default changes.
    var onDevicesChanged: (() -> Void)? { get set }
}
