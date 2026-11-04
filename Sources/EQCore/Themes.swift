/// Colour themes as plain hex data so every platform UI renders the same palette.
public struct ThemePalette: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var accent: String            // hex "#RRGGBB"
    public var gradient: [String]        // visualizer / curve gradient, low → high
    public var background: [String]?     // nil = follow system appearance
    public var isDark: Bool { background != nil }

    public static let all: [ThemePalette] = [
        ThemePalette(id: "classic", name: "Classic", accent: "#0A84FF", gradient: ["#64D2FF", "#0A84FF", "#5E5CE6"], background: nil),
        ThemePalette(id: "neon", name: "Neon Rave", accent: "#00F5D4", gradient: ["#00F5D4", "#9B5DE5", "#F15BB5"], background: ["#0B0B1A", "#151133"]),
        ThemePalette(id: "synthwave", name: "Synthwave", accent: "#FF2A6D", gradient: ["#05D9E8", "#D300C5", "#FF2A6D"], background: ["#1A0B2E", "#2B0F3F"]),
        ThemePalette(id: "ember", name: "Ember", accent: "#FF9F1C", gradient: ["#FFBF69", "#FF9F1C", "#E71D36"], background: ["#140B07", "#24120A"]),
        ThemePalette(id: "sunset", name: "Sunset", accent: "#FF7A59", gradient: ["#FFC857", "#FF7A59", "#E84855"], background: nil),
        ThemePalette(id: "ocean", name: "Ocean", accent: "#00B4D8", gradient: ["#90E0EF", "#00B4D8", "#0077B6"], background: nil),
        ThemePalette(id: "forest", name: "Forest", accent: "#40916C", gradient: ["#B7E4C7", "#52B788", "#2D6A4F"], background: nil),
        ThemePalette(id: "mono", name: "Graphite", accent: "#8E8E93", gradient: ["#D1D1D6", "#8E8E93", "#48484A"], background: nil),
    ]

    public static func named(_ id: String) -> ThemePalette { all.first { $0.id == id } ?? all[0] }
}
