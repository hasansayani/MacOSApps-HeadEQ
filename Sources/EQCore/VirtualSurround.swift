/// Virtual surround for headphones: simulates a pair of stereo speakers in
/// front of you. Each ear hears its own speaker directly plus the opposite
/// speaker slightly later (interaural time difference) and duller (head
/// shadow), plus a few early room reflections for "outside the head" depth.

public struct SurroundSettings: Codable, Equatable, Sendable {
    public var enabled = false
    public var speakerAngle: Double = 30      // degrees from centre (10…60)
    public var amount: Double = 0.6           // level of the opposite-speaker path (0…1)
    public var room: Double = 0.15            // early reflections (0…1)
    public var headShadowHz: Double = 1800    // low-pass of the opposite path

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SurroundSettings()
        enabled = c.value(.enabled, d.enabled)
        speakerAngle = c.value(.speakerAngle, d.speakerAngle)
        amount = c.value(.amount, d.amount)
        room = c.value(.room, d.room)
        headShadowHz = c.value(.headShadowHz, d.headShadowHz)
    }

    public static let presets: [(name: String, angle: Double, amount: Double, room: Double)] = [
        ("Studio monitors", 30, 0.6, 0.15),
        ("Near-field", 20, 0.5, 0.08),
        ("Wide stage", 45, 0.7, 0.22),
        ("Living room", 35, 0.65, 0.4),
    ]

    /// Interaural time difference for a source at `speakerAngle` (Woodworth, head radius 8.75 cm).
    public var itdSeconds: Double {
        let a = max(0, min(90, speakerAngle)) * Double.pi / 180
        return 0.0875 / 343 * (a + sin(a))
    }

    public func realtime(sampleRate: Double) -> RealtimeSurround {
        var r = RealtimeSurround()
        r.itdSamples = max(1, min(SurroundStage.crossCapacity - 1, Int((itdSeconds * sampleRate).rounded())))
        r.shadowCoef = Float(1 - exp(-2 * Double.pi * max(200, headShadowHz) / sampleRate))
        r.cross = Float(max(0, min(1, amount)))
        r.room = Float(max(0, min(1, room)) * 0.35)
        let tapsMS: [Double] = [7.3, 11.9, 17.1, 23.7]
        r.tap0 = min(SurroundStage.roomCapacity - 1, Int(tapsMS[0] / 1000 * sampleRate))
        r.tap1 = min(SurroundStage.roomCapacity - 1, Int(tapsMS[1] / 1000 * sampleRate))
        r.tap2 = min(SurroundStage.roomCapacity - 1, Int(tapsMS[2] / 1000 * sampleRate))
        r.tap3 = min(SurroundStage.roomCapacity - 1, Int(tapsMS[3] / 1000 * sampleRate))
        r.roomDamp = Float(1 - exp(-2 * Double.pi * 5000 / sampleRate))
        return r
    }
}

public struct RealtimeSurround: Sendable {
    public var itdSamples = 13
    public var shadowCoef: Float = 0.2
    public var cross: Float = 0.6
    public var room: Float = 0.05
    public var tap0 = 350, tap1 = 571, tap2 = 821, tap3 = 1138
    public var roomDamp: Float = 0.48
    public init() {}
}

public final class SurroundStage {
    static let crossCapacity = 512      // > max ITD (~0.66 ms) at 384 kHz
    static let roomCapacity = 16_384    // > 24 ms at 384 kHz

    public var params = RealtimeSurround()
    private let crossL: UnsafeMutablePointer<Float>, crossR: UnsafeMutablePointer<Float>
    private let roomBuf: UnsafeMutablePointer<Float>
    private var crossIndex = 0, roomIndex = 0
    private var shadowL: Float = 0, shadowR: Float = 0
    private var dampL: Float = 0, dampR: Float = 0

    public init() {
        crossL = .allocate(capacity: Self.crossCapacity); crossL.initialize(repeating: 0, count: Self.crossCapacity)
        crossR = .allocate(capacity: Self.crossCapacity); crossR.initialize(repeating: 0, count: Self.crossCapacity)
        roomBuf = .allocate(capacity: Self.roomCapacity); roomBuf.initialize(repeating: 0, count: Self.roomCapacity)
    }

    deinit { crossL.deallocate(); crossR.deallocate(); roomBuf.deallocate() }

    /// Bytes held by this stage (shown on the Features page).
    public static var memoryBytes: Int { (2 * crossCapacity + roomCapacity) * MemoryLayout<Float>.size }

    @inline(__always)
    public func process(_ l: inout Float, _ r: inout Float) {
        let p = params
        let cm = Self.crossCapacity - 1, rm = Self.roomCapacity - 1
        crossL[crossIndex] = l; crossR[crossIndex] = r
        let d = (crossIndex - p.itdSamples) & cm
        // Opposite speaker: delayed + head-shadow low-pass.
        shadowL += p.shadowCoef * (crossR[d] - shadowL)   // reaches left ear from right speaker
        shadowR += p.shadowCoef * (crossL[d] - shadowR)
        crossIndex = (crossIndex + 1) & cm

        var outL = l + p.cross * shadowL
        var outR = r + p.cross * shadowR

        if p.room > 0 {
            roomBuf[roomIndex] = (l + r) * 0.5
            let i = roomIndex
            let eL = roomBuf[(i - p.tap0) & rm] * 0.8 + roomBuf[(i - p.tap2) & rm] * 0.5
            let eR = roomBuf[(i - p.tap1) & rm] * 0.7 + roomBuf[(i - p.tap3) & rm] * 0.4
            dampL += p.roomDamp * (eL - dampL)
            dampR += p.roomDamp * (eR - dampR)
            outL += p.room * dampL
            outR += p.room * dampR
            roomIndex = (roomIndex + 1) & rm
        }
        // Keep centred (mono) content at the same loudness.
        let norm = 1 / (1 + p.cross * 0.75 + p.room * 0.6)
        l = outL * norm
        r = outR * norm
    }
}
