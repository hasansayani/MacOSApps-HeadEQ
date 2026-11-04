import AppKit
import EQCore
import HeadEQArt
import SwiftUI

// MARK: - App info / versioning

enum AppInfo {
    static var name: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "HeadEQ" }
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0" }
    static var commit: String? { Bundle.main.object(forInfoDictionaryKey: "HEQGitCommit") as? String }
    static var fullVersion: String { "Version \(version) (\(build))" + (commit.map { " · \($0)" } ?? "") }
}

// MARK: - Appearance preferences (Dock icon, menu bar icon)

enum MenuBarIconStyle: String, CaseIterable, Identifiable {
    case glyph, sliders, headphones, waveform, dial, ear
    var id: String { rawValue }
    var title: String {
        switch self {
        case .glyph: return "HeadEQ"
        case .sliders: return "Sliders"
        case .headphones: return "Headphones"
        case .waveform: return "Waveform"
        case .dial: return "Dial"
        case .ear: return "Ear"
        }
    }
    var symbol: String? {
        switch self {
        case .glyph: return nil
        case .sliders: return "slider.vertical.3"
        case .headphones: return "headphones"
        case .waveform: return "waveform"
        case .dial: return "dial.medium"
        case .ear: return "ear"
        }
    }
}

enum Prefs {
    static let appIconStyle = "appIconStyle"          // "classic" | "theme" | <theme id>
    static let menuBarIcon = "menuBarIconStyle"
    static let showMenuBarIcon = "showMenuBarIcon"
    static let menuBarShowsPreset = "menuBarShowsPreset"
    static let showInDock = "showInDock"
}

@MainActor
enum AppIcon {
    static let menuGlyph: NSImage = {
        let img = IconArt.menuGlyph(size: 36).map { NSImage(cgImage: $0, size: NSSize(width: 18, height: 18)) } ?? NSImage()
        img.isTemplate = true
        return img
    }()

    static func image(style: String, themeID: String) -> NSImage? {
        let paletteID = style == "theme" ? themeID : style
        let gradient = ThemePalette.named(paletteID).gradient
        return IconArt.appIcon(size: 512, gradient: gradient).map { NSImage(cgImage: $0, size: NSSize(width: 512, height: 512)) }
    }

    /// Apply Dock visibility + Dock icon from preferences.
    static func apply() {
        let d = UserDefaults.standard
        let dock = d.object(forKey: Prefs.showInDock) as? Bool ?? true
        if !dock, !(d.object(forKey: Prefs.showMenuBarIcon) as? Bool ?? true) {
            d.set(true, forKey: Prefs.showMenuBarIcon)   // never leave the app unreachable
        }
        NSApp.setActivationPolicy(dock ? .regular : .accessory)
        let style = d.string(forKey: Prefs.appIconStyle) ?? "classic"
        NSApp.applicationIconImage = style == "classic" ? nil : image(style: style, themeID: d.string(forKey: "themeID") ?? "classic")
    }
}

// MARK: - Settings window (⌘,)

struct SettingsView: View {
    @EnvironmentObject var model: EQModel
    @EnvironmentObject var updates: UpdateChecker
    @AppStorage("themeID") private var themeID = "classic"
    @AppStorage(Prefs.appIconStyle) private var iconStyle = "classic"
    @AppStorage(Prefs.menuBarIcon) private var menuIcon = MenuBarIconStyle.glyph.rawValue
    @AppStorage(Prefs.showMenuBarIcon) private var showMenuBar = true
    @AppStorage(Prefs.menuBarShowsPreset) private var showPreset = false
    @AppStorage(Prefs.showInDock) private var showInDock = true

    var body: some View {
        TabView {
            Form {
                Section("Startup") {
                    Toggle("Launch HeadEQ at login", isOn: $model.settings.features.launchAtLogin)
                }
                Section("Updates") {
                    Toggle("Check for updates automatically", isOn: $model.settings.features.autoUpdates)
                    HStack {
                        Button("Check now") { Task { await updates.check() } }
                        Text(updates.status).font(.caption).foregroundStyle(.secondary)
                    }
                    if let u = updates.available {
                        Button("Download HeadEQ \(u.version.description)") { updates.openDownload() }.buttonStyle(.borderedProminent)
                    }
                    Text(AppInfo.fullVersion).font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                Section("Theme") {
                    Picker("Color theme", selection: $themeID) {
                        ForEach(ThemePalette.all) { Text($0.name).tag($0.id) }
                    }
                }
                Section("App icon") {
                    Picker("Dock icon", selection: $iconStyle) {
                        Text("Classic").tag("classic")
                        Text("Match color theme").tag("theme")
                        Divider()
                        ForEach(ThemePalette.all.filter { $0.id != "classic" }) { Text($0.name).tag($0.id) }
                    }
                    HStack(spacing: 10) {
                        ForEach(["classic", "neon", "synthwave", "ember", "ocean", "forest"], id: \.self) { id in
                            if let img = AppIcon.image(style: id, themeID: themeID) {
                                Image(nsImage: img).resizable().frame(width: 44, height: 44)
                                    .overlay(RoundedRectangle(cornerRadius: 10)
                                        .stroke(currentIconID == id ? Color.accentColor : .clear, lineWidth: 2))
                                    .onTapGesture { iconStyle = id }
                                    .help(ThemePalette.named(id).name)
                            }
                        }
                    }
                    Toggle("Show in Dock", isOn: $showInDock)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Appearance", systemImage: "paintpalette") }

            Form {
                Section("Menu bar") {
                    Toggle("Show menu bar icon", isOn: $showMenuBar)
                        .disabled(!showInDock)
                        .help(showInDock ? "" : "Required while the Dock icon is hidden")
                    Picker("Icon", selection: $menuIcon) {
                        ForEach(MenuBarIconStyle.allCases) { style in
                            Label {
                                Text(style.title)
                            } icon: {
                                if let s = style.symbol { Image(systemName: s) } else { Image(nsImage: AppIcon.menuGlyph) }
                            }
                            .tag(style.rawValue)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    Toggle("Show current preset name next to the icon", isOn: $showPreset)
                    Text("The icon dims when the equalizer is off.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
        }
        .frame(width: 520, height: 420)
        .onChange(of: showInDock) { _, _ in AppIcon.apply() }
        .onChange(of: iconStyle) { _, _ in AppIcon.apply() }
        .onChange(of: themeID) { _, _ in AppIcon.apply() }
    }

    private var currentIconID: String { iconStyle == "theme" ? themeID : iconStyle }
}

/// Menu-bar label honouring the icon preferences.
struct MenuBarLabel: View {
    @EnvironmentObject var model: EQModel
    @AppStorage(Prefs.menuBarIcon) private var menuIcon = MenuBarIconStyle.glyph.rawValue
    @AppStorage(Prefs.menuBarShowsPreset) private var showPreset = false

    var body: some View {
        let style = MenuBarIconStyle(rawValue: menuIcon) ?? .glyph
        HStack(spacing: 4) {
            if let s = style.symbol { Image(systemName: s) } else { Image(nsImage: AppIcon.menuGlyph) }
            if showPreset { Text(model.currentMusicPreset?.name ?? "Custom") }
        }
        .opacity(model.settings.enabled ? 1 : 0.45)
    }
}

// MARK: - About

struct AboutView: View {
    @EnvironmentObject var updates: UpdateChecker
    @AppStorage("themeID") private var themeID = "classic"

    var body: some View {
        VStack(spacing: 12) {
            if let img = AppIcon.image(style: "classic", themeID: themeID) {
                Image(nsImage: img).resizable().frame(width: 96, height: 96)
            }
            Text(AppInfo.name).font(.title.bold())
            Text(AppInfo.fullVersion).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            HStack {
                Button("Check for Updates") { Task { await updates.check() } }.controlSize(.small)
                if let u = updates.available { Button("Get \(u.version.description)") { updates.openDownload() }.controlSize(.small) }
            }
            if !updates.status.isEmpty { Text(updates.status).font(.caption).foregroundStyle(.secondary) }
            Text("A system-wide equalizer tuned for your headphones — with measured headphone corrections, music presets, hearing protection and Background Sounds controls.")
                .multilineTextAlignment(.center).font(.callout).fixedSize(horizontal: false, vertical: true)
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Credits").font(.headline)
                credit("Headphone measurements", "AutoEQ project (Jaakko Pasanen) and its measurement sources: oratory1990, crinacle, Rtings and others.")
                credit("Filter design", "Robert Bristow-Johnson, “Audio EQ Cookbook”.")
                credit("Exposure guidance", "NIOSH recommended exposure limit (85 dBA, 8 h, 3 dB exchange rate).")
                credit("System audio", "Core Audio process taps (macOS 14.2+).")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            Text("Not a medical device. Sound-level and dose figures are estimates.")
                .font(.caption).foregroundStyle(.secondary)
            Text("© 2026 HeadEQ contributors").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 440)
    }

    private func credit(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption.bold())
            Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
