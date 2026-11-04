/// Background / ambient sounds (noise, rain, ocean…) that help mask
/// distractions or tinnitus. On macOS this drives the system Accessibility
/// feature; other platforms can implement it natively (iOS has the same
/// feature but no public API — a port could ship its own noise generator).

public struct BackgroundSound: Identifiable, Hashable, Sendable {
    public var id: String      // stable identifier (e.g. "group-5" or an asset name)
    public var name: String
    public var group: Int

    public init(id: String, name: String, group: Int) {
        self.id = id; self.name = name; self.group = group
    }
}

public struct BackgroundSoundsState: Equatable, Sendable {
    public var available = false
    public var enabled = false
    public var selectedSoundID: String?
    public var volume: Double = 0.5               // 0…1
    public var playWithMedia = false
    public var mediaVolume: Double = 0.2          // 0…1, used while other audio plays
    public var stopOnLock = true
    public var timerEnabled = false
    public var timerSeconds: Double = 3600
    public var tinnitusFilterEnabled = false
    /// Tinnitus EQ: a 2-D pad. x −1…1 → centre pitch 50 Hz…18 kHz (0 = 1 kHz);
    /// y −1…1 → filter width (narrow…wide).
    public var tinnitusX: Double = 0
    public var tinnitusY: Double = 0
    public var tinnitusFrequency: Double = 1000
    public var tinnitusWidth: Double = 0.58
    public var tinnitusFine = false          // fine (multi-band) vs coarse shaping
    public var tinnitusBalance: Double = 0   // −1 left … +1 right
    /// When the stop timer is running: seconds since 2001-01-01 (reference date) at which sound stops.
    public var timerEndReference: Double?

    public init() {}

    /// Seconds left on the running stop-timer, if any.
    public func timerRemaining(nowReference: Double) -> Double? {
        guard enabled, timerEnabled, let end = timerEndReference, end > nowReference else { return nil }
        return end - nowReference
    }
}

public protocol BackgroundSoundsBackend: AnyObject {
    var sounds: [BackgroundSound] { get }
    func read() -> BackgroundSoundsState
    func setEnabled(_ on: Bool)
    func select(_ sound: BackgroundSound)
    func setVolume(_ v: Double)
    func setPlayWithMedia(_ on: Bool)
    func setMediaVolume(_ v: Double)
    func setStopOnLock(_ on: Bool)
    func setTimer(enabled: Bool, seconds: Double)
    func setTinnitusFilter(_ on: Bool)
    func setTinnitusPoint(x: Double, y: Double)
    func setTinnitusFine(_ fine: Bool)
    func setTinnitusBalance(_ balance: Double)
}
