/// Where a headphone tuning comes from — shown in the Expert panel.
public struct TuningSource: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case measured        // derived from a real measurement (e.g. AutoEQ)
        case approximation   // HeadEQ's hand-made approximation of published measurements
        case generic         // type-based starting curve (no model-specific data)
        case userCreated     // built from scratch by the user
        case modified        // user edits on top of another profile
    }

    public var kind: Kind
    public var measuredBy: String?   // e.g. "oratory1990", "crinacle on 711"
    public var database: String?     // e.g. "AutoEQ"
    public var target: String?       // target curve the correction aims for
    public var url: String?          // where to inspect the source data
    public var basedOn: String?      // profile this one was derived from

    public init(kind: Kind, measuredBy: String? = nil, database: String? = nil, target: String? = nil,
                url: String? = nil, basedOn: String? = nil) {
        self.kind = kind; self.measuredBy = measuredBy; self.database = database
        self.target = target; self.url = url; self.basedOn = basedOn
    }

    public static let approximation = TuningSource(
        kind: .approximation, database: "HeadEQ built-in",
        target: "Harman-style neutral (approx.)")
    public static let generic = TuningSource(
        kind: .generic, database: "HeadEQ built-in", target: "Typical correction for this headphone type")
    public static let userCreated = TuningSource(kind: .userCreated)

    public static func autoEQ(measuredBy: String, path: String, kind: HeadphoneKind) -> TuningSource {
        TuningSource(kind: .measured, measuredBy: measuredBy, database: "AutoEQ",
                     target: AutoEQ.defaultTarget(for: kind),
                     url: AutoEQ.browseURL + path)
    }

    public var title: String {
        switch kind {
        case .measured: return "Measured"
        case .approximation: return "Approximation"
        case .generic: return "Generic starter"
        case .userCreated: return "Your own tuning"
        case .modified: return "Modified"
        }
    }

    /// One-line human summary, e.g. "Measured by oratory1990 · AutoEQ database".
    public var summary: String {
        switch kind {
        case .measured:
            return ["Measured by \(measuredBy ?? "unknown")", database.map { "\($0) database" }]
                .compactMap { $0 }.joined(separator: " · ")
        case .approximation:
            return "Hand-tuned approximation of published measurements — not a direct measurement"
        case .generic:
            return "No model-specific data; typical curve for this headphone type"
        case .userCreated:
            return "Created by you"
        case .modified:
            return "Your edits on top of \(basedOn ?? "another profile")"
        }
    }
}
