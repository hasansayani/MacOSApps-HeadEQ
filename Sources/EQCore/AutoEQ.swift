/// Parsing + search for the AutoEQ project's open headphone database
/// (github.com/jaakkopasanen/AutoEq, measurement-based corrections for
/// thousands of headphones). Pure string handling — networking lives in the
/// platform layer, so every port can reuse this.
public enum AutoEQ {
    public static let baseURL = "https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/results/"
    public static let indexURL = baseURL + "INDEX.md"
    /// Human-browsable location of a result folder.
    public static let browseURL = "https://github.com/jaakkopasanen/AutoEq/tree/master/results/"

    /// Target curve AutoEQ's published results aim for, by headphone type.
    public static func defaultTarget(for kind: HeadphoneKind) -> String {
        switch kind {
        case .inEar, .earbud: return "Harman in-ear (AutoEQ default)"
        default: return "Harman over-ear (AutoEQ default)"
        }
    }

    /// Export a chain as Equalizer APO / AutoEQ "ParametricEQ.txt" text.
    public static func exportParametricEQ(filters: [FilterSpec], preamp: Double) -> String {
        func f(_ v: Double, _ digits: Int) -> String {
            var p = 1.0; for _ in 0..<digits { p *= 10 }
            let r = (v * p).rounded() / p
            return digits == 0 ? String(Int(r)) : String(r)
        }
        var lines = ["Preamp: \(f(preamp, 1)) dB"]
        for (i, x) in filters.enumerated() where abs(x.gain) >= 0.01 {
            let t = x.type == .peak ? "PK" : x.type == .lowShelf ? "LSC" : "HSC"
            lines.append("Filter \(i + 1): ON \(t) Fc \(f(x.frequency, 0)) Hz Gain \(f(x.gain, 1)) dB Q \(f(x.q, 2))")
        }
        return lines.joined(separator: "\n")
    }

    /// Measurement sources, most trusted first (used to rank duplicates).
    static let sourceRank = ["oratory1990", "crinacle", "Rtings", "Innerfidelity", "Super Review", "Headphone.com Legacy"]

    public struct Entry: Identifiable, Hashable, Sendable {
        public var id: String { path }
        public var name: String
        public var path: String        // URL-encoded, relative to `baseURL`
        public var source: String
        public var kind: HeadphoneKind

        /// URL of the "<Name> ParametricEQ.txt" file for this entry.
        public var parametricEQURL: String {
            let encodedName = path.split(separator: "/").last.map(String.init) ?? ""
            return AutoEQ.baseURL + path + "/" + encodedName + "%20ParametricEQ.txt"
        }
    }

    /// Parse INDEX.md lines like:
    /// `- [Sony WH-1000XM3](./oratory1990/over-ear/Sony%20WH-1000XM3) by oratory1990`
    public static func parseIndex(_ text: String) -> [Entry] {
        var entries: [Entry] = []
        for line in text.split(separator: "\n") where line.hasPrefix("- [") {
            guard let closeName = line.firstRange(of: "](") else { continue }
            let name = String(line[line.index(line.startIndex, offsetBy: 3)..<closeName.lowerBound])
            let rest = line[closeName.upperBound...]
            guard let closePath = rest.firstRange(of: ") by ") else { continue }
            var path = String(rest[..<closePath.lowerBound])
            if path.hasPrefix("./") { path.removeFirst(2) }
            let source = String(rest[closePath.upperBound...]).trimmed
            entries.append(Entry(name: name, path: path, source: source, kind: kind(fromPath: path)))
        }
        return entries
    }

    static func kind(fromPath path: String) -> HeadphoneKind {
        let p = path.lowercased()
        if p.contains("earbud") { return .earbud }
        if p.contains("in-ear") { return .inEar }
        if p.contains("on-ear") { return .onEar }
        return .overEar
    }

    /// Fuzzy search. Every query token must appear in the name; exact matches
    /// and trusted measurement sources rank first; one result per name.
    public static func search(_ query: String, in entries: [Entry], limit: Int = 25) -> [Entry] {
        let tokens = tokenize(query)
        guard !tokens.isEmpty else { return [] }
        let compactQuery = tokens.joined()
        var best: [String: (Entry, Int)] = [:]
        for e in entries {
            let nameTokens = tokenize(e.name)
            let compactName = nameTokens.joined()
            guard tokens.allSatisfy({ t in nameTokens.contains { $0.hasPrefix(t) } || compactName.contains(t) }) else { continue }
            var score = 0
            if compactName == compactQuery { score += 1000 }
            if compactName.hasPrefix(compactQuery) { score += 200 }
            score -= compactName.count                                   // shorter = closer
            score += 50 - 10 * (sourceRank.firstIndex { e.source.hasPrefix($0) } ?? 5)
            if e.name.contains("(") { score -= 20 }                       // variants (ANC off, sample 2…)
            if let existing = best[e.name], existing.1 >= score { continue }
            best[e.name] = (e, score)
        }
        return best.values.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    /// Parse an AutoEQ / Equalizer APO "ParametricEQ.txt".
    public static func parseParametricEQ(_ text: String) -> (preamp: Double, filters: [FilterSpec]) {
        var preamp = 0.0
        var filters: [FilterSpec] = []
        for raw in text.split(separator: "\n") {
            let words = raw.split(separator: " ").map(String.init)
            if words.first == "Preamp:", words.count > 1 { preamp = Double(words[1]) ?? 0; continue }
            guard words.first == "Filter", words.contains("ON") else { continue }
            func value(after key: String) -> Double? {
                guard let i = words.firstIndex(of: key), i + 1 < words.count else { return nil }
                return Double(words[i + 1])
            }
            let type: FilterType
            if words.contains("PK") || words.contains("PEQ") { type = .peak }
            else if words.contains("LSC") || words.contains("LS") { type = .lowShelf }
            else if words.contains("HSC") || words.contains("HS") { type = .highShelf }
            else { continue }
            guard let fc = value(after: "Fc"), let gain = value(after: "Gain") else { continue }
            filters.append(FilterSpec(type, fc, gain, q: value(after: "Q") ?? (type == .peak ? 1 : 0.707)))
        }
        return (preamp, filters)
    }

    /// Build a custom profile from a downloaded entry.
    public static func profile(from entry: Entry, parametricEQ text: String, id: String) -> HeadphoneProfile? {
        let parsed = parseParametricEQ(text)
        guard !parsed.filters.isEmpty else { return nil }
        return HeadphoneProfile(id: id, name: entry.name, kind: entry.kind,
                                matchKeywords: HeadphoneNaming.keywords(for: entry.name),
                                filters: Array(parsed.filters.prefix(HeadphoneProfile.maxFilters)),
                                note: "Measured correction downloaded from AutoEQ.", isBuiltIn: false,
                                source: .autoEQ(measuredBy: entry.source, path: entry.path, kind: entry.kind))
    }

    public static func tokenize(_ s: String) -> [String] {
        var out: [String] = [], cur = ""
        for ch in s.lowercased() {
            if ch.isLetter || ch.isNumber { cur.append(ch) } else if !cur.isEmpty { out.append(cur); cur = "" }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }
}

/// Offline helpers for creating a profile from just a headphone name.
public enum HeadphoneNaming {
    static let brands = ["apple", "sony", "bose", "sennheiser", "beyerdynamic", "audio-technica", "audio technica",
                         "akg", "beats", "samsung", "jabra", "jbl", "skullcandy", "anker", "soundcore", "shure",
                         "hifiman", "focal", "grado", "koss", "philips", "nothing", "google", "marshall", "b&o",
                         "bang & olufsen", "bowers & wilkins", "b&w", "moondrop", "fiio", "sony"]

    /// Device-name keywords: the model without the brand (Bluetooth names usually omit it).
    public static func keywords(for name: String) -> [String] {
        var model = name.lowercased().trimmed
        if let paren = model.firstIndex(of: "(") { model = String(model[..<paren]).trimmed }
        for b in brands where model.hasPrefix(b + " ") { model = String(model.dropFirst(b.count + 1)).trimmed; break }
        return model.isEmpty ? [] : [model]
    }

    /// Guess the headphone type from its name (used when no measurement exists).
    public static func guessKind(_ name: String) -> HeadphoneKind {
        let n = " " + name.lowercased() + " "
        let earbud = ["airpods ", "airpods)", "earpods", "open fit", "open-fit", "open ear"]
        let inEar = ["buds", "pods", "iem", "in-ear", "in ear", "wf-", "earphone", "sport", "powerbeats", "fit pro",
                     "studio buds", "tws", "earfun", "liberty", "elite "]
        let onEar = ["on-ear", "on ear", "porta pro", "solo", "ksc75", "sr60", "sr80"]
        if n.contains("airpods pro") { return .inEar }
        if earbud.contains(where: n.contains) { return .earbud }
        if inEar.contains(where: n.contains) { return .inEar }
        if onEar.contains(where: n.contains) { return .onEar }
        if n.contains("speaker") { return .speaker }
        return .overEar
    }

    /// A starting profile for an unknown model: the generic correction for its type.
    public static func starterProfile(named name: String, id: String) -> HeadphoneProfile {
        let kind = guessKind(name)
        let genericID: String
        switch kind {
        case .inEar: genericID = "generic-inear"
        case .earbud: genericID = "generic-earbud"
        case .speaker: genericID = "laptop-speakers"
        case .overEar, .onEar: genericID = "generic-over"
        }
        let base = HeadphoneProfile.builtIn.first { $0.id == genericID }!
        return HeadphoneProfile(id: id, name: name.trimmed, kind: kind, matchKeywords: keywords(for: name),
                                filters: base.filters,
                                note: "Starter curve for \(kind.rawValue.lowercased()) headphones — fine-tune with Edit…",
                                isBuiltIn: false,
                                source: TuningSource(kind: .generic, database: "HeadEQ built-in",
                                                     target: base.provenance.target, basedOn: base.name))
    }
}

extension Substring {
    /// Foundation-free substring search.
    func firstRange(of needle: String) -> Range<Index>? {
        let n = Array(needle)
        guard !n.isEmpty else { return nil }
        var i = startIndex
        while i < endIndex {
            var j = i, k = 0
            while k < n.count, j < endIndex, self[j] == n[k] { j = index(after: j); k += 1 }
            if k == n.count { return i..<j }
            i = index(after: i)
        }
        return nil
    }
}

extension StringProtocol {
    var trimmed: String {
        String(drop { $0 == " " || $0 == "\t" || $0 == "\r" }.reversed().drop { $0 == " " || $0 == "\t" || $0 == "\r" }.reversed())
    }
}
