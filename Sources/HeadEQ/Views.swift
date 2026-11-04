import EQCore
import SwiftUI

// MARK: - Describe → preset

struct DescribeBar: View {
    @EnvironmentObject var model: EQModel
    @Environment(\.theme) private var theme
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(theme.accent)
                TextField("Describe what you're listening to — e.g. “EDM on Bose SoundSport, more bass, less harsh”",
                          text: $text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(create)
                Button("Create Preset", action: create)
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let g = model.lastGenerated {
                HStack(spacing: 6) {
                    Text("Created “\(model.currentMusicPreset?.name ?? g.name)”:").font(.caption.bold())
                    ForEach(g.understood, id: \.self) { item in
                        Text(item).font(.caption)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(theme.accent.opacity(0.18)))
                    }
                    Text("— drag the sliders to tweak; changes save automatically.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { model.dismissGenerated() } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func create() {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        model.generatePreset(from: text)
        text = ""
    }
}

// MARK: - Cards

struct HeadphoneCard: View {
    @EnvironmentObject var model: EQModel
    @State private var editing: HeadphoneProfile?
    @State private var confirmDelete = false
    @State private var addingByName = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Profile", selection: $model.settings.headphoneProfileID) {
                    if !model.customHeadphones.isEmpty {
                        Section("My Headphones") {
                            ForEach(model.customHeadphones) { Text($0.name).tag($0.id) }
                        }
                    }
                    ForEach(HeadphoneKind.allCases, id: \.self) { kind in
                        let items = model.builtInHeadphones.filter { $0.kind == kind && $0.id != "none" }
                        if !items.isEmpty {
                            Section(kind.rawValue) { ForEach(items) { Text($0.name).tag($0.id) } }
                        }
                    }
                    Divider()
                    Text(HeadphoneProfile.none.name).tag(HeadphoneProfile.none.id)
                }
                Toggle("Auto-detect from output device", isOn: $model.settings.autoDetectHeadphones)
                HStack(spacing: 6) {
                    Badge(text: model.headphoneProfile.provenance.title,
                          color: model.headphoneProfile.provenance.kind == .measured ? .green :
                                 model.headphoneProfile.provenance.kind == .approximation ? .orange : .secondary)
                    if let by = model.headphoneProfile.provenance.measuredBy {
                        Text("by \(by)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(model.headphoneProfile.note.isEmpty ? " " : model.headphoneProfile.note)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Add by Name…") { addingByName = true }
                    Button("New…") { editing = model.newHeadphoneDraft() }
                    let current = model.headphoneProfile
                    if current.isBuiltIn {
                        Button("Customize…") {
                            editing = model.newHeadphoneDraft(basedOn: current.id == "none" ? nil : current)
                        }
                    } else {
                        Button("Edit…") { editing = current }
                        Button("Delete", role: .destructive) { confirmDelete = true }
                    }
                }
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Headphones", systemImage: "headphones")
        }
        .sheet(item: $editing) { draft in
            HeadphoneEditorView(draft: draft).environmentObject(model)
        }
        .sheet(isPresented: $addingByName) {
            AddHeadphoneView(library: model.library).environmentObject(model)
        }
        .confirmationDialog("Delete “\(model.headphoneProfile.name)”?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { model.deleteHeadphone(model.headphoneProfile) }
        }
    }
}

struct MusicCard: View {
    @EnvironmentObject var model: EQModel
    @State private var nameInput = ""
    @State private var showingSave = false
    @State private var showingRename = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Preset", selection: Binding(
                    get: { model.settings.musicPresetID },
                    set: { id in if let p = model.musicPresets.first(where: { $0.id == id }) { model.selectMusicPreset(p) } }
                )) {
                    if !model.customPresets.isEmpty {
                        Section("My Presets") { ForEach(model.customPresets) { Text($0.name).tag($0.id) } }
                    }
                    Section("Built-in") { ForEach(MusicPreset.builtIn) { Text($0.name).tag($0.id) } }
                    if model.settings.musicPresetID == EQModel.customPresetID {
                        Divider()
                        Text("Custom (unsaved)").tag(EQModel.customPresetID)
                    }
                }
                HStack {
                    Button("Save As…") { nameInput = ""; showingSave = true }
                    if let p = model.customPresets.first(where: { $0.id == model.settings.musicPresetID }) {
                        Button("Rename…") { nameInput = p.name; showingRename = true }
                        Button("Delete", role: .destructive) { model.deleteCustomPreset(p) }
                    }
                }
                .controlSize(.small)
                HStack {
                    Toggle("Auto preamp", isOn: $model.settings.autoPreamp)
                        .help("Lowers gain by the curve's highest boost so nothing clips")
                    Spacer()
                    Text(String(format: "%+.1f dB", model.effectivePreamp)).monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: $model.settings.preampDB, in: -18...6, step: 0.5) { Text("Preamp") }
                    .disabled(model.settings.autoPreamp)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Music", systemImage: "music.note")
        }
        .alert("Save Preset", isPresented: $showingSave) {
            TextField("Name", text: $nameInput)
            Button("Save") { model.saveCustomPreset(named: nameInput) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Preset", isPresented: $showingRename) {
            TextField("Name", text: $nameInput)
            Button("Rename") {
                if let p = model.currentMusicPreset { model.renameCustomPreset(p, to: nameInput) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Graphic EQ

struct BandsView: View {
    @EnvironmentObject var model: EQModel
    @Binding var step: Double

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Graphic EQ").font(.headline)
                if let p = model.currentMusicPreset, !p.isBuiltIn {
                    Text("editing “\(p.name)”").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("Reset") { model.resetBands() }.controlSize(.small)
            }
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("Bandwidth Q").font(.caption)
                    Slider(value: $model.settings.graphicQ, in: 0.5...4, step: 0.05).frame(maxWidth: 140)
                    Text(String(format: "%.2f", model.settings.graphicQ)).font(.caption).monospacedDigit().frame(width: 32)
                }
                .help("Higher Q = narrower, more surgical bands")
                Spacer()
                Picker("Step", selection: $step) {
                    Text("0.5 dB").tag(0.5)
                    Text("0.1 dB").tag(0.1)
                }
                .pickerStyle(.segmented).fixedSize()
            }
            HStack(spacing: 0) {
                ForEach(GraphicEQ.frequencies.indices, id: \.self) { i in
                    VStack(spacing: 6) {
                        Text(String(format: "%+.1f", model.settings.bandGains[i]))
                            .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                        VerticalSlider(value: Binding(get: { model.settings.bandGains[i] },
                                                      set: { model.setBand(i, gain: $0, step: step) }),
                                       range: GraphicEQ.gainRange, step: step)
                        Text(GraphicEQ.label(GraphicEQ.frequencies[i])).font(.caption.bold())
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

struct VerticalSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.5
    @Environment(\.theme) private var theme
    @FocusState private var focused: Bool

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let span = range.upperBound - range.lowerBound
            let y = h * (1 - (value - range.lowerBound) / span)
            let zeroY = h * (1 - (0 - range.lowerBound) / span)
            ZStack(alignment: .top) {
                Capsule().fill(.quaternary).frame(width: 4)
                Rectangle()
                    .fill(LinearGradient(colors: theme.gradient.reversed(), startPoint: .top, endPoint: .bottom))
                    .frame(width: 4, height: abs(zeroY - y))
                    .offset(y: min(zeroY, y))
                Rectangle().fill(.secondary).frame(width: 14, height: 1).offset(y: zeroY)
                Circle().fill(.white).overlay(Circle().stroke(focused ? theme.accent : .clear, lineWidth: 2))
                    .shadow(radius: 1.5)
                    .frame(width: 16, height: 16)
                    .offset(y: y - 8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                focused = true
                let f = 1 - min(max(g.location.y / h, 0), 1)
                value = range.lowerBound + f * span
            })
            .onTapGesture(count: 2) { value = 0 }
        }
        .frame(minHeight: 150)
        .focusable()
        .focused($focused)
        .onKeyPress(.upArrow) { value = min(range.upperBound, value + step); return .handled }
        .onKeyPress(.downArrow) { value = max(range.lowerBound, value - step); return .handled }
        .help("Drag · ↑/↓ for fine steps · double-click to reset")
    }
}

// MARK: - Output fine-tuning

struct OutputCard: View {
    @EnvironmentObject var model: EQModel

    var body: some View {
        let o = $model.settings.output
        let out = model.settings.output
        TwoColumns {
            Section2(title: "Level & stereo", icon: "slider.horizontal.3") {
                ParamSlider(title: "Output gain", value: o.gainDB, range: -12...6, step: 0.1, reset: 0) {
                    String(format: "%+.1f dB", $0)
                }
                ParamSlider(title: "Balance", value: o.balance, range: -1...1, step: 0.01, reset: 0) { v in
                    abs(v) < 0.005 ? "Center" : String(format: "%@ %d%%", v < 0 ? "L" : "R", Int(abs(v) * 100))
                }
                ParamSlider(title: "Stereo width", value: o.width, range: 0...2, step: 0.01, reset: 1) {
                    "\(Int($0 * 100))%"
                }
                .disabled(out.mono)
                HStack(spacing: 16) {
                    Toggle("Mono", isOn: o.mono)
                    Toggle("Swap L/R", isOn: o.swapChannels)
                    Toggle("Invert polarity", isOn: o.invertPolarity)
                }
            }
            Section2(title: "Crossfeed", icon: "arrow.left.arrow.right") {
                Text("Blends a little of each channel into the other, like speakers in a room. Reduces fatigue from hard-panned mixes on headphones.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ParamSlider(title: "Amount", value: o.crossfeed, range: 0...1, step: 0.01, reset: 0) {
                    $0 < 0.005 ? "Off" : "\(Int($0 * 100))%"
                }
                ParamSlider(title: "Cutoff", value: o.crossfeedCutoff, range: 300...1200, step: 10, reset: 700) {
                    "\(Int($0)) Hz"
                }
                .disabled(out.crossfeed < 0.005)
            }
        } right: {
            Section2(title: "Peak limiter", icon: "waveform.path.ecg") {
                HStack {
                    Toggle("Enabled", isOn: o.limiterEnabled)
                    Spacer()
                    LimiterMeter()
                }
                ParamSlider(title: "Ceiling", value: o.limiterCeilingDB, range: -6...0, step: 0.1, reset: -0.5) {
                    String(format: "%.1f dBFS", $0)
                }
                .disabled(!out.limiterEnabled)
                ParamSlider(title: "Release", value: o.limiterReleaseMS, range: 20...500, step: 5, reset: 120) {
                    "\(Int($0)) ms"
                }
                .disabled(!out.limiterEnabled)
            }
            Section2(title: "Device", icon: "hifispeaker") {
                SampleRatePicker()
                if model.settings.features.deviceMemory {
                    Label(model.activeDevice.flatMap { model.deviceMemory.snapshot(for: $0.uid) } != nil
                          ? "Settings are remembered for this device" : "This device's settings will be remembered",
                          systemImage: "memorychip").font(.caption).foregroundStyle(.secondary)
                    ForEach(model.deviceMemory.snapshots.sorted { $0.value.deviceName < $1.value.deviceName }, id: \.key) { uid, snap in
                        HStack {
                            Text(snap.deviceName).font(.caption)
                            Spacer()
                            Text(model.headphoneProfiles.first { $0.id == snap.headphoneProfileID }?.name ?? "—")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Button { model.forgetDevice(uid) } label: { Image(systemName: "xmark.circle") }
                                .buttonStyle(.borderless).help("Forget this device")
                        }
                    }
                }
                Text(model.activeDevice.map { "\($0.name) · \($0.transport.rawValue)\($0.isLikelyExternalDAC ? " · external DAC" : "") · \($0.channels) ch" } ?? "No device")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Reset output settings") { model.settings.output = OutputSettings() }.controlSize(.small)
            }
        }
    }
}

struct ParamSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let reset: Double
    let format: (Double) -> String

    var body: some View {
        HStack(spacing: 8) {
            Text(title).frame(width: 110, alignment: .leading)
            Slider(value: $value, in: range, step: step)
            Text(format(value)).monospacedDigit().font(.callout).foregroundStyle(.secondary)
                .frame(width: 74, alignment: .trailing)
                .onTapGesture(count: 2) { value = reset }
                .help("Double-click to reset")
        }
    }
}

struct SampleRatePicker: View {
    @EnvironmentObject var model: EQModel

    var body: some View {
        let rates = model.availableSampleRates
        HStack {
            Text("Device sample rate").frame(width: 130, alignment: .leading)
            if rates.isEmpty {
                Text("—").foregroundStyle(.secondary)
            } else {
                Picker("", selection: Binding(get: { model.currentSampleRate }, set: { model.setSampleRate($0) })) {
                    ForEach(rates, id: \.self) { Text(String(format: "%g kHz", $0 / 1000)).tag($0) }
                }
                .labelsHidden().fixedSize()
            }
            Spacer()
        }
        .help("Hardware rate of the output device (useful for USB DACs)")
    }
}

struct LimiterMeter: View {
    @EnvironmentObject var model: EQModel

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 4, paused: !model.isRunning || !model.settings.output.limiterEnabled)) { _ in
            let gr = model.isRunning && model.settings.output.limiterEnabled ? model.backend.limiterReductionDB : 0
            HStack(spacing: 4) {
                Text("GR").font(.caption2).foregroundStyle(.secondary)
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary).frame(width: 60, height: 5)
                    Capsule().fill(.orange).frame(width: CGFloat(min(1, -gr / 12)) * 60, height: 5)
                }
                Text(String(format: "%.1f", gr)).font(.caption2).monospacedDigit().frame(width: 30, alignment: .trailing)
            }
            .help("Limiter gain reduction (dB)")
        }
    }
}

// MARK: - Response curve

struct ResponseCurveView: View {
    let filters: [FilterSpec]
    let preamp: Double
    @Environment(\.theme) private var theme
    private let dbRange = 15.0
    private let freqs = FrequencyResponse.logFrequencies(count: 240)

    var body: some View {
        Canvas { ctx, size in
            let curve = FrequencyResponse.curve(filters: filters, preamp: preamp, frequencies: freqs)
            func yFor(_ db: Double) -> CGFloat { size.height / 2 - CGFloat(db / dbRange) * size.height / 2 }
            func xFor(_ f: Double) -> CGFloat { CGFloat(log10(f / 20) / log10(1000)) * size.width }

            var grid = Path()
            for db in stride(from: -12.0, through: 12, by: 6) {
                grid.move(to: CGPoint(x: 0, y: yFor(db))); grid.addLine(to: CGPoint(x: size.width, y: yFor(db)))
            }
            for f in [50.0, 100, 200, 500, 1000, 2000, 5000, 10000] {
                grid.move(to: CGPoint(x: xFor(f), y: 0)); grid.addLine(to: CGPoint(x: xFor(f), y: size.height))
            }
            ctx.stroke(grid, with: .color(.secondary.opacity(0.15)), lineWidth: 1)
            ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: yFor(0))); $0.addLine(to: CGPoint(x: size.width, y: yFor(0))) },
                       with: .color(.secondary.opacity(0.4)), lineWidth: 1)
            for (f, label) in [(100.0, "100"), (1000, "1k"), (10000, "10k")] {
                ctx.draw(Text(label).font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: xFor(f) + 10, y: size.height - 8))
            }
            for db in [-12.0, 12] {
                ctx.draw(Text("\(Int(db)) dB").font(.caption2).foregroundStyle(.secondary),
                         at: CGPoint(x: 22, y: yFor(db) + (db > 0 ? 8 : -8)))
            }

            var line = Path()
            for (i, f) in freqs.enumerated() {
                let p = CGPoint(x: xFor(f), y: yFor(max(-dbRange, min(dbRange, curve[i]))))
                i == 0 ? line.move(to: p) : line.addLine(to: p)
            }
            let shading = GraphicsContext.Shading.linearGradient(Gradient(colors: theme.gradient),
                                                                 startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0))
            ctx.stroke(line, with: shading, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
        .padding(8)
        .allowsHitTesting(false)
    }
}

// MARK: - Menu bar

struct MenuBarView: View {
    @EnvironmentObject var model: EQModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle(model.settings.enabled ? "Equalizer: On" : "Equalizer: Off", isOn: $model.settings.enabled)
        Text(model.statusText)
        Divider()
        Menu("Headphones: \(model.headphoneProfile.name)") {
            Picker("Headphones", selection: $model.settings.headphoneProfileID) {
                ForEach(model.headphoneProfiles) { Text($0.name).tag($0.id) }
            }
            .pickerStyle(.inline)
        }
        Menu("Music: \(model.currentMusicPreset?.name ?? "Custom")") {
            ForEach(model.musicPresets) { p in Button(p.name) { model.selectMusicPreset(p) } }
        }
        Toggle("Crossfeed", isOn: Binding(get: { model.settings.output.crossfeed > 0 },
                                         set: { model.settings.output.crossfeed = $0 ? 0.4 : 0 }))
        Toggle("Mono", isOn: $model.settings.output.mono)
        Toggle("Hearing protection", isOn: $model.settings.hearing.enabled)
        BackgroundSoundsMenu()
        MenuDoseText(meters: model.meters)
        Divider()
        Button("Open HeadEQ…") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Help") { openWindow(id: "help"); NSApp.activate(ignoringOtherApps: true) }
        Button("About HeadEQ") { openWindow(id: "about"); NSApp.activate(ignoringOtherApps: true) }
        SettingsLink { Text("Settings…") }
        Divider()
        Button("Quit") { model.shutdown(); NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}


private struct MenuDoseText: View {
    @ObservedObject var meters: LiveMeters
    var body: some View { Text("Today's sound dose: \(meters.dosePercent)%") }
}
