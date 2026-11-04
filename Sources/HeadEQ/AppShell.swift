import EQCore
import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case equalizer, output, system, hearing, background, expert, features
    var id: String { rawValue }

    /// Sidebar grouping.
    enum Group: String, CaseIterable { case sound = "Sound", hearing = "Hearing", tools = "Tools", app = "App" }

    var group: Group {
        switch self {
        case .equalizer, .output: return .sound
        case .hearing, .background: return .hearing
        case .expert: return .tools
        case .system, .features: return .app
        }
    }

    /// Optional feature this page belongs to (shows its on/off switch on the page).
    var featureID: String? { nil }

    var title: String {
        switch self {
        case .equalizer: return "Equalizer"
        case .output: return "Output"
        case .system: return "System Audio"
        case .hearing: return "Hearing Protection"
        case .background: return "Background Sounds"
        case .expert: return "Expert"
        case .features: return "Features"
        }
    }

    var icon: String {
        switch self {
        case .equalizer: return "slider.vertical.3"
        case .output: return "dial.medium"
        case .system: return "speaker.wave.2"
        case .hearing: return "ear"
        case .background: return "cloud.rain"
        case .expert: return "info.circle"
        case .features: return "switch.2"
        }
    }

    var subtitle: String {
        switch self {
        case .equalizer: return "Headphones, presets and the graphic EQ"
        case .output: return "Gain, stereo, crossfeed, limiter and device"
        case .system: return "Device volume, alerts, Headphone Accommodations and Transparency"
        case .hearing: return "Spike guard, level cap and today's sound dose"
        case .background: return "macOS Accessibility Background Sounds"
        case .expert: return "Where each tuning comes from, and the full signal chain"
        case .features: return "Turn optional features on or off. Off means no processing and no memory used."
        }
    }
}

/// Window shell: sidebar of pages + a detail page. Global controls (power,
/// output device, theme) live in the toolbar so every page stays uncluttered.
struct ContentView: View {
    @EnvironmentObject var model: EQModel
    @AppStorage("themeID") private var themeID = "classic"
    @AppStorage("page") private var pageID = Page.equalizer.rawValue

    private var page: Page { Page(rawValue: pageID) ?? .equalizer }

    var body: some View {
        let theme = AppTheme.named(themeID)
        NavigationSplitView {
            List(selection: Binding(get: { page }, set: { if let p = $0 { pageID = p.rawValue } })) {
                ForEach(Page.Group.allCases, id: \.self) { group in
                    Section(group.rawValue) {
                        ForEach(Page.allCases.filter { $0.group == group }) { p in
                            HStack {
                                Label(p.title, systemImage: p.icon)
                                Spacer()
                                if let f = p.featureID, !model.settings.features[isOn: f] {
                                    Text("Off").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .tag(p)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
            .safeAreaInset(edge: .bottom) { SidebarStatus().padding(12) }
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(page.title).font(.largeTitle.bold())
                        Text(page.subtitle).foregroundStyle(.secondary)
                    }
                    DoseBanner()
                    if let f = page.featureID { FeatureSwitchBar(featureID: f) }
                    if page.featureID.map({ model.settings.features[isOn: $0] }) ?? true {
                        pageContent
                    }
                }
                .padding(24)
                .frame(maxWidth: 1200, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background {
                if let bg = theme.background {
                    LinearGradient(colors: bg, startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                }
            }
            .toolbar { toolbar }
            .navigationTitle("HeadEQ")
        }
        .frame(minWidth: 980, minHeight: 680)
        .modifier(Themed(theme: theme))
        .onChange(of: themeID) { _, _ in AppIcon.apply() }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .equalizer: EqualizerPage()
        case .output: OutputCard()
        case .system: SystemAudioPage()
        case .hearing: HearingProtectionCard()
        case .background: BackgroundSoundsCard()
        case .expert: ExpertView()
        case .features: FeaturesPage()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Picker("Output", selection: $model.settings.outputDeviceUID) {
                Text("System default").tag(String?.none)
                Divider()
                ForEach(model.devices) { d in
                    Text("\(d.name)\(d.isLikelyExternalDAC ? " (DAC)" : "")").tag(Optional(d.uid))
                }
            }
            .frame(width: 220)
            .help("Output device")
            Menu {
                Picker("Theme", selection: $themeID) {
                    ForEach(ThemePalette.all) { p in
                        Label { Text(p.name) } icon: { Image(systemName: "circle.fill").foregroundStyle(Color(hex: p.accent)) }
                            .tag(p.id)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Theme", systemImage: "paintpalette")
            }
            .help("Color theme")
            HStack(spacing: 8) {
                Text(model.settings.enabled ? "Equalizer On" : "Equalizer Off")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(model.settings.enabled ? Color.primary : Color.secondary)
                    .frame(minWidth: 92, alignment: .trailing)
                Toggle("Equalizer", isOn: $model.settings.enabled)
                    .toggleStyle(.switch).labelsHidden()
            }
            .padding(.horizontal, 6)
            .help("Master switch: turn the equalizer on or off (off = completely untouched audio)")
        }
    }
}

/// All optional features with their switches and costs.
struct FeaturesPage: View {
    @EnvironmentObject var model: EQModel
    @AppStorage("page") private var pageID = Page.equalizer.rawValue

    var body: some View {
        let items = FeatureSettings.catalogue
        let half = (items.count + 1) / 2
        TwoColumns {
            ForEach(items.prefix(half)) { card($0) }
        } right: {
            ForEach(items.dropFirst(half)) { card($0) }
        }
    }

    private func card(_ f: FeatureInfo) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(f.title, systemImage: f.icon).font(.headline)
                    Spacer()
                    Toggle("", isOn: $model.settings.features[isOn: f.id]).toggleStyle(.switch).labelsHidden()
                }
                Text(f.summary).font(.callout).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Label(f.cost, systemImage: "cpu").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if let page = Page.allCases.first(where: { $0.featureID == f.id }) {
                        Button("Open") { pageID = page.rawValue }.controlSize(.small)
                    }
                }
            }
        }
    }
}

/// The on/off switch shown at the top of a feature's page.
struct FeatureSwitchBar: View {
    @EnvironmentObject var model: EQModel
    let featureID: String

    var body: some View {
        let info = FeatureSettings.catalogue.first { $0.id == featureID }
        let on = model.settings.features[isOn: featureID]
        HStack(spacing: 10) {
            Image(systemName: on ? "checkmark.circle.fill" : "power.circle").foregroundStyle(on ? .green : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(on ? "\(info?.title ?? "Feature") is on" : "\(info?.title ?? "Feature") is off").font(.callout.bold())
                Text(on ? (info?.cost ?? "") : "Turn it on to use it. While off it uses no processing or memory.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $model.settings.features[isOn: featureID]).toggleStyle(.switch).labelsHidden()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }
}

/// Status + quick facts at the bottom of the sidebar.
struct SidebarStatus: View {
    @EnvironmentObject var model: EQModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(model.statusText, systemImage: icon)
                .font(.caption).foregroundStyle(color).lineLimit(3)
            Divider()
            row("headphones", model.headphoneProfile.name)
            row("music.note", model.currentMusicPreset?.name ?? "Custom")
            row("ear", "Dose today \(Int(model.exposure.dose * 100))%")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon).font(.caption).foregroundStyle(.secondary).lineLimit(1)
    }

    private var icon: String {
        switch model.status {
        case .running: return "waveform"
        case .stopped: return "pause.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var color: Color {
        switch model.status {
        case .running: return .green
        case .stopped: return .secondary
        case .failed: return .orange
        }
    }
}

/// Main page: describe bar on top, then controls (left) and sound (right).
struct EqualizerPage: View {
    @EnvironmentObject var model: EQModel
    @Environment(\.theme) private var theme
    @AppStorage("visualizerStyle") private var vizStyle = VisualizerStyle.bars.rawValue
    @AppStorage("showEQCurve") private var showCurve = true
    @AppStorage("bandStep") private var bandStep = 0.5

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DescribeBar()
            TwoColumns(leftWidth: 340) {
                HeadphoneCard()
                MusicCard()
            } right: {
                GroupBox {
                    VStack(spacing: 8) {
                        HStack {
                            Picker("Visualizer", selection: $vizStyle) {
                                ForEach(VisualizerStyle.allCases) { Text($0.title).tag($0.rawValue) }
                            }
                            .pickerStyle(.segmented).labelsHidden().fixedSize()
                            Toggle("EQ curve", isOn: $showCurve).toggleStyle(.checkbox)
                            Spacer()
                        }
                        ZStack {
                            RoundedRectangle(cornerRadius: 12).fill(.black.opacity(theme.palette.isDark ? 0.35 : 0.06))
                            VisualizerView(style: VisualizerStyle(rawValue: vizStyle) ?? .bars, backend: model.backend)
                                .padding(8)
                            if showCurve {
                                ResponseCurveView(filters: model.filters, preamp: model.effectivePreamp)
                            }
                        }
                        .frame(height: 200)
                    }
                } label: {
                    Label("Sound", systemImage: "waveform")
                }
                GroupBox {
                    BandsView(step: $bandStep).padding(.top, 2)
                } label: {
                    Label("Graphic EQ", systemImage: "slider.vertical.3")
                }
            }
        }
    }
}

/// Two-column page layout: a left column and a flexible right column, each a
/// vertical stack of sections.
struct TwoColumns<Left: View, Right: View>: View {
    var leftWidth: CGFloat? = nil
    @ViewBuilder var left: Left
    @ViewBuilder var right: Right

    init(leftWidth: CGFloat? = nil, @ViewBuilder _ left: () -> Left, @ViewBuilder right: () -> Right) {
        self.leftWidth = leftWidth
        self.left = left()
        self.right = right()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) { left }
                .frame(width: leftWidth)
                .frame(maxWidth: leftWidth == nil ? .infinity : nil, alignment: .topLeading)
            VStack(alignment: .leading, spacing: 16) { right }
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

/// A titled group box section used throughout the pages.
struct Section2<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        } label: {
            Label(title, systemImage: icon).font(.headline)
        }
    }
}
