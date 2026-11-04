/// Import / export / sync of user presets and headphone profiles.
/// Formats: HeadEQ library JSON (.headeq), AutoEQ / Equalizer APO
/// "ParametricEQ.txt", and Wavelet / APO "GraphicEQ:" lines.

public struct PresetLibrary: Codable, Equatable, Sendable {
    public var format = "headeq-library"
    public var version = 1
    public var exportedAt = ""
    public var presets: [MusicPreset] = []
    public var headphones: [HeadphoneProfile] = []

    public init(presets: [MusicPreset] = [], headphones: [HeadphoneProfile] = [], exportedAt: String = "") {
        self.presets = presets.filter { !$0.isBuiltIn }
        self.headphones = headphones.filter { !$0.isBuiltIn }
        self.exportedAt = exportedAt
    }

    public var isEmpty: Bool { presets.isEmpty && headphones.isEmpty }

    /// Union by id. Items already present locally are kept (local wins); new ones are added.
    public func merged(with other: PresetLibrary) -> (library: PresetLibrary, added: Int) {
        var out = self
        let haveP = Set(presets.map(\.id)), haveH = Set(headphones.map(\.id))
        let newP = other.presets.filter { !haveP.contains($0.id) && !$0.isBuiltIn }
        let newH = other.headphones.filter { !haveH.contains($0.id) && !$0.isBuiltIn }
        out.presets += newP
        out.headphones += newH
        return (out, newP.count + newH.count)
    }
}

public enum ImportedItem: Equatable, Sendable {
    case library(PresetLibrary)
    case headphone(HeadphoneProfile)
    case preset(MusicPreset)
}

public enum PresetFormats {
    /// Parse "GraphicEQ: 20 -1.2; 21 -1.3; …" into (frequency, gain) points.
    public static func parseGraphicEQ(_ text: String) -> [(Double, Double)] {
        guard let line = text.split(separator: "\n").first(where: { $0.hasPrefix("GraphicEQ:") }) else { return [] }
        return line.dropFirst("GraphicEQ:".count).split(separator: ";").compactMap { pair in
            let nums = pair.split(separator: " ").compactMap { Double($0) }
            return nums.count >= 2 ? (nums[0], nums[1]) : nil
        }.sorted { $0.0 < $1.0 }
    }

    /// Sample a GraphicEQ curve at the 10 band centres (log-frequency interpolation).
    public static func bandGains(fromGraphicEQ points: [(Double, Double)]) -> [Double] {
        guard !points.isEmpty else { return MusicPreset.flat.gains }
        return GraphicEQ.frequencies.map { f in
            if f <= points.first!.0 { return points.first!.1 }
            if f >= points.last!.0 { return points.last!.1 }
            let i = points.firstIndex { $0.0 >= f }!
            let (f0, g0) = points[i - 1], (f1, g1) = points[i]
            let t = (log(f) - log(f0)) / (log(f1) - log(f0))
            let g = g0 + (g1 - g0) * t
            return min(max((g * 10).rounded() / 10, GraphicEQ.gainRange.lowerBound), GraphicEQ.gainRange.upperBound)
        }
    }

    /// Export a filter chain as a GraphicEQ line (127 log-spaced points, like AutoEQ).
    public static func exportGraphicEQ(filters: [FilterSpec], preamp: Double) -> String {
        let freqs = FrequencyResponse.logFrequencies(count: 127, from: 20, to: 20_000)
        let curve = FrequencyResponse.curve(filters: filters, preamp: preamp, frequencies: freqs)
        let parts = zip(freqs, curve).map { f, g in "\(Int(f.rounded())) \((g * 10).rounded() / 10)" }
        return "GraphicEQ: " + parts.joined(separator: "; ")
    }

    /// Detect and parse an imported text file. `decodeJSON` is supplied by the platform (JSON is Foundation-specific).
    public static func parse(text: String, fileName: String, id: String,
                             decodeJSON: (String) -> PresetLibrary?) -> ImportedItem? {
        let trimmed = text.trimmed
        let baseName = fileName.split(separator: "/").last.map { name -> String in
            var n = String(name)
            for suffix in [" ParametricEQ.txt", " GraphicEQ.txt", ".headeq", ".json", ".txt"] where n.hasSuffix(suffix) {
                n = String(n.dropLast(suffix.count))
            }
            return n
        } ?? "Imported"
        if trimmed.hasPrefix("{"), let lib = decodeJSON(trimmed), lib.format == "headeq-library" { return .library(lib) }
        if trimmed.contains("GraphicEQ:") {
            let gains = bandGains(fromGraphicEQ: parseGraphicEQ(trimmed))
            return .preset(MusicPreset(id: id, name: baseName, gains: gains, isBuiltIn: false,
                                       origin: "Imported from GraphicEQ file “\(fileName)”"))
        }
        let parsed = AutoEQ.parseParametricEQ(trimmed)
        if !parsed.filters.isEmpty {
            return .headphone(HeadphoneProfile(id: id, name: baseName, kind: HeadphoneNaming.guessKind(baseName),
                                               matchKeywords: HeadphoneNaming.keywords(for: baseName),
                                               filters: Array(parsed.filters.prefix(HeadphoneProfile.maxFilters)),
                                               note: "Imported from “\(fileName)”.", isBuiltIn: false,
                                               source: TuningSource(kind: .userCreated, database: "Imported file", basedOn: fileName)))
        }
        return nil
    }
}
