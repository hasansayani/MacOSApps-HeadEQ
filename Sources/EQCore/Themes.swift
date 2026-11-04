/// Colour themes as plain hex data so every platform UI renders the same palette.
public struct ThemePalette: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var accent: String            // hex "#RRGGBB"
    public var gradient: [String]        // visualizer / curve gradient, low → high
    public var background: [String]?     // nil = follow system appearance
    /// Retro player skin: vertical LED-style spectrum (green → yellow → red) drawn in segments.
    public var retro = false
    public var group = "HeadEQ"
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

        // Classic desktop-player skins (Winamp-style looks; not affiliated with Winamp).
        ThemePalette(id: "skin-classic", name: "Classic Base", accent: "#00D800",
                     gradient: ["#18B818", "#7FD000", "#D8D800", "#F07000", "#E01010"],
                     background: ["#2A2A39", "#101018"], retro: true, group: "Player skins"),
        ThemePalette(id: "skin-modern", name: "Modern", accent: "#8AB4E8",
                     gradient: ["#2E5E9E", "#5A8CCB", "#A9C9EE", "#E6F1FC"],
                     background: ["#2C3646", "#141A24"], retro: true, group: "Player skins"),
        ThemePalette(id: "skin-bento", name: "Bento", accent: "#F0A030",
                     gradient: ["#3A7BD5", "#47B0E0", "#F0A030", "#F06A1E"],
                     background: ["#2B2B2B", "#151515"], retro: true, group: "Player skins"),
        ThemePalette(id: "skin-lcd", name: "Green LCD", accent: "#7CFC5A",
                     gradient: ["#1F7A1F", "#3FBF3F", "#7CFC5A", "#C8FFB0"],
                     background: ["#0A140A", "#030803"], retro: true, group: "Player skins"),
        ThemePalette(id: "skin-ice", name: "Ice Steel", accent: "#9FD3F5",
                     gradient: ["#3C5A78", "#6E93B8", "#9FD3F5", "#FFFFFF"],
                     background: ["#3A4350", "#1C222B"], retro: true, group: "Player skins"),
    ]

    public static var groups: [String] { all.reduce(into: [String]()) { if !$0.contains($1.group) { $0.append($1.group) } } }

    public static func named(_ id: String) -> ThemePalette { all.first { $0.id == id } ?? all[0] }
}
