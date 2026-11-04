import EQCore
import SwiftUI

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let v = UInt64(h, radix: 16) ?? 0
        self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255, opacity: 1)
    }
}

struct AppTheme {
    let palette: ThemePalette
    var accent: Color { Color(hex: palette.accent) }
    var gradient: [Color] { palette.gradient.map(Color.init(hex:)) }
    var background: [Color]? { palette.background?.map(Color.init(hex:)) }

    static func named(_ id: String) -> AppTheme { AppTheme(palette: .named(id)) }
}

private struct ThemeKey: EnvironmentKey { static let defaultValue = AppTheme.named("classic") }
extension EnvironmentValues {
    var theme: AppTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

struct Themed: ViewModifier {
    let theme: AppTheme
    func body(content: Content) -> some View {
        content
            .environment(\.theme, theme)
            .tint(theme.accent)
            .background {
                if let bg = theme.background {
                    LinearGradient(colors: bg, startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                }
            }
            .preferredColorScheme(theme.palette.isDark ? .dark : nil)
    }
}
