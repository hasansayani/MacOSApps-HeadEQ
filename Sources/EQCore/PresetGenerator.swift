/// Turns a plain-language description ("EDM on Bose SoundSport, more bass")
/// into an editable preset: a headphone profile + a music curve.
/// Rule-based and offline so it runs identically on every platform.

public struct GeneratedPreset: Sendable {
    public var name: String
    public var gains: [Double]
    public var headphone: HeadphoneProfile?
    /// Human-readable list of what was understood, e.g. ["Genre: Electronic", "Headphones: Bose SoundSport"].
    public var understood: [String]
    /// Provenance text stored with the resulting preset.
    public var origin: String
}

public enum PresetGenerator {
    // Genre synonyms → built-in music preset id. Longer phrases first.
    static let genres: [(words: [String], presetID: String, label: String)] = [
        (["drum and bass", "drum & bass", "dnb", "edm", "electronic", "electro", "house", "techno",
          "trance", "dubstep", "rave", "dance", "club", "synthwave", "future bass"], "electronic", "Electronic / EDM"),
        (["hip hop", "hip-hop", "hiphop", "rap", "trap", "drill", "r&b", "rnb"], "hiphop", "Hip-Hop / R&B"),
        (["metal", "rock", "punk", "grunge", "indie rock", "alternative"], "rock", "Rock"),
        (["k-pop", "kpop", "pop", "top 40"], "pop", "Pop"),
        (["jazz", "blues", "soul", "funk"], "jazz", "Jazz / Soul"),
        (["classical", "orchestra", "orchestral", "symphony", "opera", "piano", "soundtrack", "score"], "classical", "Classical"),
        (["acoustic", "folk", "country", "singer-songwriter", "unplugged"], "acoustic", "Acoustic"),
        (["podcast", "audiobook", "speech", "talk", "news", "lecture", "dialogue", "youtube"], "spoken", "Spoken word"),
        (["gaming", "game", "fps", "footsteps", "shooter"], "gaming", "Gaming"),
        (["movie", "film", "netflix", "late night", "night", "quiet", "low volume"], "loudness", "Movies / Late night"),
    ]

    // Type words → generic headphone profile id (used when no model matched).
    static let headphoneTypes: [(words: [String], profileID: String)] = [
        (["iem", "in-ear", "in ear", "earphone", "sport", "running", "gym"], "generic-inear"),
        (["earbud", "earbuds", "buds", "open fit", "open-fit"], "generic-earbud"),
        (["over-ear", "over ear", "headphone", "headset", "cans", "studio"], "generic-over"),
        (["laptop", "macbook", "speaker"], "laptop-speakers"),
    ]

    // Tone adjustments: per-band deltas (32 64 125 250 500 1k 2k 4k 8k 16k).
    // `negative` phrases are checked first and suppress the positive ones of the same group.
    struct Modifier { let group: String; let words: [String]; let delta: [Double]; let label: String }
    static let modifiers: [Modifier] = [
        Modifier(group: "bass", words: ["less bass", "too much bass", "too boomy", "boomy", "muddy", "lean", "tight bass"],
                 delta: [-3, -2.5, -1.5, -1, 0, 0, 0, 0, 0, 0], label: "Less bass"),
        Modifier(group: "bass", words: ["more bass", "bassy", "bass heavy", "heavy bass", "punchy", "punch", "boom", "sub bass",
                                        "sub-bass", "thump", "rumble", "drop", "drops"],
                 delta: [3, 3, 1.5, 0, 0, 0, 0, 0, 0, 0], label: "More bass"),
        Modifier(group: "treble", words: ["less treble", "harsh", "sibilant", "sibilance", "fatiguing", "too bright", "piercing",
                                          "shrill", "tinny"],
                 delta: [0, 0, 0, 0, 0, 0, -0.5, -2, -2.5, -1.5], label: "Smoother treble"),
        Modifier(group: "treble", words: ["more treble", "bright", "sparkle", "airy", "crisp", "detail", "detailed", "clarity"],
                 delta: [0, 0, 0, 0, 0, 0, 0.5, 1.5, 2, 2.5], label: "More detail / air"),
        Modifier(group: "warmth", words: ["warm", "smooth", "chill", "relax", "lofi", "lo-fi", "mellow", "cozy"],
                 delta: [0.5, 1, 1.5, 1.5, 0.5, 0, -0.5, -1.5, -1.5, -1], label: "Warmer"),
        Modifier(group: "vocals", words: ["vocal", "vocals", "voice", "singer", "lyrics", "clear dialogue"],
                 delta: [0, 0, -0.5, 0, 1, 2, 2, 1, 0, 0], label: "Clearer vocals"),
        Modifier(group: "energy", words: ["workout", "gym", "running", "party", "energetic", "hype", "loud", "festival"],
                 delta: [2, 2, 1, 0, -1, -0.5, 0, 1, 1.5, 1.5], label: "Energetic (V-shape)"),
    ]

    public static func generate(from description: String,
                                headphones: [HeadphoneProfile] = HeadphoneProfile.builtIn,
                                presets: [MusicPreset] = MusicPreset.builtIn) -> GeneratedPreset {
        let text = " " + description.lowercased() + " "
        var compact = normalize(description)
        // Shorthand people use for Sony's over-ears: "sony xm3" → WH-1000XM3.
        if !compact.contains("wf") {
            for n in ["3", "4", "5", "6"] where compact.contains("xm" + n) && !compact.contains("wh1000xm" + n) {
                compact += "wh1000xm" + n
            }
        }
        var understood: [String] = []

        // 1. Headphones: exact model first (keywords or a custom profile's name), then a generic type.
        var headphone: HeadphoneProfile?
        headphone = headphones.first { p in
            p.id != HeadphoneProfile.none.id &&
            (p.matchKeywords.contains { compact.contains(normalize($0)) } ||
             (!p.isBuiltIn && compact.contains(normalize(p.name))))
        }
        if headphone == nil,
           let type = headphoneTypes.first(where: { $0.words.contains { contains(text, $0) } }) {
            headphone = headphones.first { $0.id == type.profileID }
        }
        if let h = headphone { understood.append("Headphones: \(h.name)") }

        // 2. Genre base curve.
        var gains = MusicPreset.flat.gains
        var genreName: String?
        if let g = genres.first(where: { $0.words.contains { contains(text, $0) } }),
           let base = presets.first(where: { $0.id == g.presetID }) {
            gains = base.gains
            genreName = g.label
            understood.append("Genre: \(g.label)")
        }

        // 3. Tone modifiers.
        var usedGroups = Set<String>()
        for m in modifiers where !usedGroups.contains(m.group) {
            if m.words.contains(where: { contains(text, $0) }) {
                usedGroups.insert(m.group)
                for i in gains.indices { gains[i] += m.delta[i] }
                understood.append(m.label)
            }
        }
        gains = gains.map { min(max(($0 * 2).rounded() / 2, GraphicEQ.gainRange.lowerBound), GraphicEQ.gainRange.upperBound) }

        if understood.isEmpty { understood.append("Nothing specific recognised — started from Flat") }

        let parts = [genreName.map { g in String(g.prefix { $0 != "/" }.reversed().drop { $0 == " " }.reversed()) },
                     headphone.map { $0.name.replacingPrefix("Apple ", with: "") }].compactMap { $0 }
        let name = parts.isEmpty ? "My Preset" : parts.joined(separator: " · ")
        let origin = "Generated from “\(description.trimmed)” → " + understood.joined(separator: ", ")
        return GeneratedPreset(name: name, gains: gains, headphone: headphone, understood: understood, origin: origin)
    }

    /// Word-boundary-ish containment so "rap" doesn't match "trap door"… mostly.
    static func contains(_ text: String, _ phrase: String) -> Bool {
        for sep in [" ", ",", ".", "!", "?", ";", ":", "/", "(", ")", "-"] {
            for end in [" ", ",", ".", "!", "?", ";", ":", "/", "(", ")", "s "] {
                if text.contains(sep + phrase + end) { return true }
            }
        }
        return false
    }

    static func normalize(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") }.map(Character.init))
    }
}

extension String {
    func replacingPrefix(_ prefix: String, with replacement: String) -> String {
        hasPrefix(prefix) ? replacement + dropFirst(prefix.count) : self
    }
}
