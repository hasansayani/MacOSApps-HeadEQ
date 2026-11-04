/// Built-in presets. Two independent layers are combined at runtime:
///  1. HeadphoneProfile – corrects a headphone's frequency response toward a
///     neutral target (Harman-style). Parametric filters.
///  2. MusicPreset – a taste/genre curve on the 10-band graphic EQ.

public enum GraphicEQ {
    public static let frequencies: [Double] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    public static let q: Double = 1.41          // ≈ one-octave bandwidth
    public static let gainRange: ClosedRange<Double> = -12...12

    public static func label(_ f: Double) -> String {
        f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))"
    }

    public static func filters(gains: [Double], q: Double = GraphicEQ.q) -> [FilterSpec] {
        zip(frequencies, gains).map { FilterSpec.peak($0, $1, q: q) }
    }
}

public struct MusicPreset: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var gains: [Double]    // one per GraphicEQ band
    public var isBuiltIn: Bool
    /// How this curve was made, e.g. "Generated from “EDM on Bose SoundSport”". Optional for old data.
    public var origin: String?

    public init(id: String, name: String, gains: [Double], isBuiltIn: Bool = true, origin: String? = nil) {
        precondition(gains.count == GraphicEQ.frequencies.count)
        self.id = id; self.name = name; self.gains = gains; self.isBuiltIn = isBuiltIn; self.origin = origin
    }

    public var originDescription: String {
        origin ?? (isBuiltIn ? "HeadEQ built-in genre/taste curve (subjective, not measurement-based)" : "Saved by you")
    }

    public static let flat = MusicPreset(id: "flat", name: "Flat", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0])

    //                                                              32   64  125  250  500   1k   2k   4k   8k  16k
    public static let builtIn: [MusicPreset] = [
        flat,
        MusicPreset(id: "bass",       name: "Bass Boost",   gains: [ 6,   5,   3.5, 1.5, 0,   0,   0,   0,   0,   0]),
        MusicPreset(id: "treble",     name: "Treble Boost", gains: [ 0,   0,   0,   0,   0,   0.5, 1.5, 3,   4.5, 5]),
        MusicPreset(id: "vocal",      name: "Vocal",        gains: [-2,  -1.5,-1,   0.5, 2,   3,   3,   2,   0.5, 0]),
        MusicPreset(id: "rock",       name: "Rock",         gains: [ 4,   3.5, 2,  -0.5,-1.5,-1,   1,   2.5, 3.5, 3.5]),
        MusicPreset(id: "pop",        name: "Pop",          gains: [-1,   1,   2.5, 3,   2,   0,  -0.5,-0.5, 1,   1.5]),
        MusicPreset(id: "electronic", name: "Electronic",   gains: [ 5,   4.5, 2,   0,  -1.5, 0,  -0.5, 1.5, 3.5, 4]),
        MusicPreset(id: "hiphop",     name: "Hip-Hop",      gains: [ 5.5, 4.5, 2,   2.5,-1,  -0.5, 1,  -0.5, 1.5, 2.5]),
        MusicPreset(id: "jazz",       name: "Jazz",         gains: [ 3,   2,   1,   1.5,-1,  -1,   0,   1,   2,   3]),
        MusicPreset(id: "classical",  name: "Classical",    gains: [ 3,   2.5, 2,   1,  -0.5,-0.5, 0,   1.5, 2.5, 3]),
        MusicPreset(id: "acoustic",   name: "Acoustic",     gains: [ 3,   3,   2,   0.5, 1,   1,   2,   2.5, 2,   1.5]),
        MusicPreset(id: "loudness",   name: "Late Night / Loudness", gains: [5, 4, 2, 0, -1, -1, 0, 1, 3, 3.5]),
        MusicPreset(id: "spoken",     name: "Podcast / Spoken", gains: [-4, -3, -1, 0.5, 2, 3, 3, 2, 0, -1]),
        MusicPreset(id: "gaming",     name: "Gaming (footsteps)", gains: [-2, -1, -1, -0.5, 0, 1, 3, 4, 2.5, 1]),
    ]
}

public enum HeadphoneKind: String, Codable, Sendable, CaseIterable {
    case overEar = "Over-ear", onEar = "On-ear", inEar = "In-ear", earbud = "Earbuds", speaker = "Speakers"
}

/// Headphone correction profile.
///
/// The model profiles are *approximations* of published measurement-based
/// corrections (in the style of AutoEQ, toward a Harman-like target). Units
/// vary between production batches, and fit and seal change bass a lot, so
/// treat them as a starting point.
public struct HeadphoneProfile: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var kind: HeadphoneKind
    /// Case-insensitive substrings matched against the OS output-device name.
    public var matchKeywords: [String]
    public var filters: [FilterSpec]
    public var note: String
    public var isBuiltIn: Bool
    /// Provenance. Optional so profiles saved by older versions still decode.
    public var source: TuningSource?

    public var provenance: TuningSource { source ?? (isBuiltIn ? .approximation : .userCreated) }

    /// Room left for correction filters after the graphic EQ bands.
    public static let maxFilters = EQProcessor.maxFilters - GraphicEQ.frequencies.count

    public init(id: String, name: String, kind: HeadphoneKind, matchKeywords: [String] = [],
                filters: [FilterSpec], note: String = "", isBuiltIn: Bool = true, source: TuningSource? = nil) {
        self.id = id; self.name = name; self.kind = kind
        self.matchKeywords = matchKeywords; self.filters = filters; self.note = note
        self.isBuiltIn = isBuiltIn; self.source = source
    }

    public static let none = HeadphoneProfile(id: "none", name: "No correction", kind: .overEar,
                                              filters: [], note: "Bypass headphone correction.",
                                              source: TuningSource(kind: .generic, database: "—", target: "None (flat)"))

    public static let builtIn: [HeadphoneProfile] = [
        none,
        // Ordered so more specific keywords win (e.g. "AirPods Pro" before "AirPods").
        HeadphoneProfile(id: "airpods-pro-2", name: "Apple AirPods Pro 2", kind: .inEar,
                         matchKeywords: ["airpods pro"],
                         filters: [.lowShelf(105, -1.5), .peak(200, -1.5, q: 0.9), .peak(2800, 2.0, q: 1.4),
                                   .peak(5500, -2.0, q: 3), .peak(9000, 2.0, q: 2), .highShelf(10000, -1)],
                         note: "Tames slight upper-bass warmth, fills in the upper-mid dip."),
        HeadphoneProfile(id: "airpods-max", name: "Apple AirPods Max", kind: .overEar,
                         matchKeywords: ["airpods max"],
                         filters: [.lowShelf(105, -1.5), .peak(600, 1.5, q: 1), .peak(2500, 2.0, q: 1.5),
                                   .peak(6500, -2.0, q: 4), .highShelf(10000, 1)],
                         note: "Adds presence; lifts the recessed lower-mids slightly."),
        HeadphoneProfile(id: "airpods", name: "Apple AirPods (3rd/4th gen)", kind: .earbud,
                         matchKeywords: ["airpods"],
                         filters: [.lowShelf(105, 4.0), .peak(2500, -1.5, q: 1.5), .peak(6000, 2.0, q: 2),
                                   .highShelf(10000, -1)],
                         note: "Open-fit buds leak bass; this restores low end."),
        HeadphoneProfile(id: "beats-studio-pro", name: "Beats Studio Pro", kind: .overEar,
                         matchKeywords: ["beats studio"],
                         filters: [.lowShelf(105, -3), .peak(300, -1.5, q: 1), .peak(3000, 2.0, q: 1.5),
                                   .highShelf(10000, 1)],
                         note: "Pulls back the bass emphasis."),
        HeadphoneProfile(id: "sony-wf-xm5", name: "Sony WF-1000XM5", kind: .inEar,
                         matchKeywords: ["wf-1000xm5"],
                         filters: [.lowShelf(105, -2.5), .peak(250, -1.5, q: 1), .peak(3200, 3.0, q: 1.4),
                                   .peak(7500, -1.5, q: 3)],
                         note: "Leaner bass, more upper-mid presence."),
        HeadphoneProfile(id: "sony-xm5", name: "Sony WH-1000XM5", kind: .overEar,
                         matchKeywords: ["wh-1000xm5", "1000xm5"],
                         filters: [.peak(200, -3.0, q: 0.9), .peak(1500, 1.0, q: 1), .peak(3000, 3.0, q: 1.5),
                                   .peak(8000, -2.0, q: 3), .highShelf(10000, 2)],
                         note: "Reduces mid-bass bloat, restores vocal presence."),
        HeadphoneProfile(id: "sony-xm4", name: "Sony WH-1000XM4", kind: .overEar,
                         matchKeywords: ["wh-1000xm4", "1000xm4"],
                         filters: [.lowShelf(105, -2), .peak(250, -3.0, q: 0.8), .peak(2800, 4.0, q: 1.4),
                                   .highShelf(10000, 2)],
                         note: "Reduces bass/low-mid boom, adds clarity."),
        HeadphoneProfile(id: "sony-xm3", name: "Sony WH-1000XM3", kind: .overEar,
                         matchKeywords: ["wh-1000xm3", "wh1000xm3"],
                         filters: [.lowShelf(105, -4.1, q: 0.7), .peak(143, -5.9, q: 1.02), .peak(697, -2.8, q: 0.92),
                                   .peak(1411, 6.2, q: 1.1), .peak(4315, 4.4, q: 1.98), .peak(5637, -1.2, q: 5.83),
                                   .peak(6657, 2.1, q: 6), .peak(9032, -1.5, q: 2), .highShelf(10000, 1.4, q: 0.7),
                                   .peak(55, 0.3, q: 2.24)],
                         note: "Cuts the heavy mid-bass, restores the recessed mids and presence.",
                         source: .autoEQ(measuredBy: "oratory1990", path: "oratory1990/over-ear/Sony%20WH-1000XM3", kind: .overEar)),
        HeadphoneProfile(id: "bose-qc-ultra", name: "Bose QuietComfort Ultra", kind: .overEar,
                         matchKeywords: ["qc ultra", "quietcomfort ultra"],
                         filters: [.peak(150, -1.0, q: 1), .peak(1000, 1.0, q: 1), .peak(4000, -2.0, q: 2),
                                   .highShelf(10000, 1.5)],
                         note: "Mild touch-ups; already close to neutral."),
        HeadphoneProfile(id: "bose-qc45", name: "Bose QC45 / QC Headphones", kind: .overEar,
                         matchKeywords: ["qc45", "bose qc"],
                         filters: [.lowShelf(105, 1.5), .peak(1800, 1.5, q: 1.5), .peak(5000, -2.5, q: 2.5),
                                   .highShelf(10000, 2)],
                         note: "Smooths treble, adds a touch of air."),
        HeadphoneProfile(id: "hd600", name: "Sennheiser HD 600 / HD 650", kind: .overEar,
                         matchKeywords: ["hd 600", "hd600", "hd 650", "hd650"],
                         filters: [.lowShelf(105, 5.5), .peak(2000, -1.0, q: 1.5), .peak(3800, -1.5, q: 2),
                                   .peak(9000, 2.0, q: 3), .highShelf(10000, 1)],
                         note: "Restores sub-bass roll-off of open-backs."),
        HeadphoneProfile(id: "dt770", name: "Beyerdynamic DT 770 Pro", kind: .overEar,
                         matchKeywords: ["dt 770", "dt770"],
                         filters: [.lowShelf(105, 2), .peak(300, -1.5, q: 1), .peak(5500, 2.0, q: 2),
                                   .peak(8500, -5.0, q: 4), .highShelf(10000, -2)],
                         note: "Tames the sharp 8–9 kHz treble peak."),
        HeadphoneProfile(id: "m50x", name: "Audio-Technica ATH-M50x", kind: .overEar,
                         matchKeywords: ["m50x", "ath-m50"],
                         filters: [.peak(150, -1.5, q: 0.8), .peak(2000, 1.5, q: 1.2), .peak(5000, -2.0, q: 2),
                                   .peak(9000, 3.0, q: 3)],
                         note: "Evens out the scooped mids."),
        HeadphoneProfile(id: "bose-soundsport", name: "Bose SoundSport / SoundSport Free", kind: .inEar,
                         matchKeywords: ["soundsport", "sound sport"],
                         filters: [.lowShelf(105, -1.5), .peak(180, -1.5, q: 1), .peak(1200, 1.0, q: 1.2),
                                   .peak(3000, 2.5, q: 1.4), .peak(7000, -2.0, q: 3), .highShelf(10000, 1.5)],
                         note: "StayHear tips don't fully seal: trims warm bass, lifts vocal presence and air."),
        HeadphoneProfile(id: "powerbeats-pro", name: "Beats Powerbeats Pro", kind: .inEar,
                         matchKeywords: ["powerbeats"],
                         filters: [.lowShelf(105, -2.5), .peak(250, -1, q: 1), .peak(2800, 2.0, q: 1.4),
                                   .peak(6500, -1.5, q: 3)],
                         note: "Reins in the bass, adds clarity."),
        HeadphoneProfile(id: "galaxy-buds", name: "Samsung Galaxy Buds Pro", kind: .inEar,
                         matchKeywords: ["galaxy buds"],
                         filters: [.lowShelf(105, -1.5), .peak(3000, 2.5, q: 1.4), .peak(6000, -2.0, q: 3)],
                         note: "Adds presence, softens sibilance."),
        // Generic fall-backs by type.
        HeadphoneProfile(id: "generic-over", name: "Generic Over-ear", kind: .overEar,
                         filters: [.peak(200, -1.5, q: 0.8), .peak(3000, 1.5, q: 1.2), .highShelf(10000, 1)],
                         note: "Gentle clarity curve for unknown over-ears.", source: .generic),
        HeadphoneProfile(id: "generic-inear", name: "Generic In-ear (sealed)", kind: .inEar,
                         filters: [.lowShelf(105, -1), .peak(3000, 2.0, q: 1.4), .peak(7000, -1.5, q: 3)],
                         note: "Compensates for the typical ear-canal resonance shift.", source: .generic),
        HeadphoneProfile(id: "generic-earbud", name: "Generic Earbuds (open-fit)", kind: .earbud,
                         filters: [.lowShelf(105, 4), .peak(4000, -1, q: 1.5)],
                         note: "Restores bass lost to open fit.", source: .generic),
        HeadphoneProfile(id: "laptop-speakers", name: "Laptop Speakers", kind: .speaker,
                         filters: [.lowShelf(150, 3), .peak(400, -1.5, q: 1), .peak(3000, 1.5, q: 1.2)],
                         note: "Mild warmth without overdriving small drivers.", source: .generic),
    ]

    /// Pick a profile by matching the OS output-device name.
    public static func match(deviceName: String, in profiles: [HeadphoneProfile] = builtIn) -> HeadphoneProfile? {
        let name = deviceName.lowercased()
        return profiles.first { p in p.matchKeywords.contains { name.contains($0) } }
    }
}
