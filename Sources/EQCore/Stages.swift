/// Optional DSP stages. A `StageSet` is allocated on a non-real-time thread
/// only for the features that are switched on, then handed to the audio
/// thread; switched-off features have no object, no buffers and no per-sample
/// work. Parameter changes go through `StageParams` (plain values) so moving
/// a slider never allocates.

public final class StageSet {
    public let surround: SurroundStage?
    public let leveler: LevelerStage?
    public let personal: PersonalEQStage?

    public init(surround: Bool = false, leveler: Bool = false, personal: Bool = false) {
        self.surround = surround ? SurroundStage() : nil
        self.leveler = leveler ? LevelerStage() : nil
        self.personal = personal ? PersonalEQStage() : nil
    }

    public convenience init(_ sig: StageSignature) { self.init(surround: sig.surround, leveler: sig.leveler, personal: sig.personal) }

    /// Which stages exist (used to decide whether a new set must be built).
    public var signature: StageSignature {
        StageSignature(surround: surround != nil, leveler: leveler != nil, personal: personal != nil)
    }
}

public struct StageSignature: Equatable, Sendable {
    public var surround = false
    public var leveler = false
    public var personal = false
    public init(surround: Bool = false, leveler: Bool = false, personal: Bool = false) {
        self.surround = surround; self.leveler = leveler; self.personal = personal
    }
    public var isEmpty: Bool { !surround && !leveler && !personal }
}

/// Real-time parameters for all stages (copied by value; never allocates).
public struct StageParams: Sendable {
    public var surround = RealtimeSurround()
    public var leveler = RealtimeLeveler()
    public var personal = RealtimePersonal()
    public init() {}
}

/// What the platform layer asks the backend to run. `nil` = feature off.
public struct ProcessingConfig: Equatable, Sendable {
    public var surround: SurroundSettings?
    public var leveler: LevelerSettings?
    public var personal: PersonalCorrectionSettings?
    public init(surround: SurroundSettings? = nil, leveler: LevelerSettings? = nil, personal: PersonalCorrectionSettings? = nil) {
        self.surround = surround; self.leveler = leveler; self.personal = personal
    }

    public var signature: StageSignature {
        StageSignature(surround: surround != nil, leveler: leveler != nil, personal: personal != nil)
    }

    public func realtime(sampleRate: Double) -> StageParams {
        var p = StageParams()
        if let surround { p.surround = surround.realtime(sampleRate: sampleRate) }
        if let leveler { p.leveler = leveler.realtime(sampleRate: sampleRate) }
        if let personal { p.personal = personal.realtime(sampleRate: sampleRate) }
        return p
    }
}
