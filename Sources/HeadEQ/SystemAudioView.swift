import EQCore
import SwiftUI

struct SystemAudioPage: View {
    @EnvironmentObject var model: EQModel
    @EnvironmentObject var sysModel: SystemAudioModel

    var body: some View {
        let sys = sysModel.sys, acc = sysModel.acc
        let device = model.activeDevice
        TwoColumns {
            Section2(title: "Output device", icon: "hifispeaker") {
                Text(device.map { "\($0.name) · \($0.transport.rawValue)" } ?? "No device").font(.callout.bold())
                if let v = sys.volume, let device {
                    ParamSlider(title: "Volume", value: Binding(get: { v }, set: { x in sysModel.change { sysModel.sounds.setVolume(x, device: device) } }),
                                range: 0...1, step: 0.01, reset: 0.5) { "\(Int($0 * 100))%" }
                } else {
                    Text("This device has no software volume control.").font(.caption).foregroundStyle(.secondary)
                }
                if let m = sys.muted, let device {
                    Toggle("Mute", isOn: Binding(get: { m }, set: { x in sysModel.change { sysModel.sounds.setMuted(x, device: device) } }))
                }
                if let b = sys.balance, let device {
                    ParamSlider(title: "Balance", value: Binding(get: { b }, set: { x in sysModel.change { sysModel.sounds.setBalance(x, device: device) } }),
                                range: 0...1, step: 0.01, reset: 0.5) { v in
                        abs(v - 0.5) < 0.005 ? "Center" : String(format: "%@ %d%%", v < 0.5 ? "L" : "R", Int(abs(v - 0.5) * 200))
                    }
                }
                Text("Hardware/device controls. HeadEQ's own gain and balance are on the Output page.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section2(title: "Alerts & interface sounds", icon: "bell") {
                ParamSlider(title: "Alert volume", value: Binding(get: { sys.alertVolume }, set: { x in sysModel.change { sysModel.sounds.setAlertVolume(x) } }),
                            range: 0...1, step: 0.01, reset: 1) { "\(Int($0 * 100))%" }
                Toggle("Play user interface sound effects", isOn: Binding(get: { sys.uiSounds }, set: { x in sysModel.change { sysModel.sounds.setUISounds(x) } }))
                Toggle("Play feedback when volume is changed", isOn: Binding(get: { sys.volumeFeedback }, set: { x in sysModel.change { sysModel.sounds.setVolumeFeedback(x) } }))
                Toggle("Flash the screen when an alert sound occurs", isOn: Binding(get: { sys.flashOnAlert }, set: { x in sysModel.change { sysModel.sounds.setFlashOnAlert(x) } }))
                Button("Open Sound Settings…") { SystemSounds.openSoundSettings() }.controlSize(.small)
            }
        } right: {
            Section2(title: "Headphone Accommodations", icon: "ear.and.waveform") {
                if !acc.available {
                    Text("Not available on this macOS version.").foregroundStyle(.secondary)
                } else {
                    Toggle("Headphone Accommodations", isOn: Binding(get: { acc.enabled }, set: { x in sysModel.change { sysModel.accommodations.setEnabled(x) } }))
                        .toggleStyle(.switch)
                    Text("Apple's hearing-tailored tuning for supported Apple and Beats headphones. Works alongside HeadEQ's EQ.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Group {
                        Picker("Tune audio for", selection: Binding(get: { acc.shape }, set: { x in sysModel.change { sysModel.accommodations.setTuning(shape: x, level: acc.level) } })) {
                            Text("Balanced Tone").tag(0)
                            Text("Vocal Range").tag(1)
                            Text("Brightness").tag(2)
                        }
                        Picker("Boost soft sounds", selection: Binding(get: { acc.level }, set: { x in sysModel.change { sysModel.accommodations.setTuning(shape: acc.shape, level: x) } })) {
                            Text("Slight").tag(0)
                            Text("Moderate").tag(1)
                            Text("Strong").tag(2)
                        }
                        .pickerStyle(.segmented)
                    }
                    .disabled(!acc.enabled)
                }
            }
            Section2(title: "Transparency mode (AirPods)", icon: "airpods.pro") {
                if let address = acc.transparencyAddress {
                    Toggle("Custom transparency mode", isOn: Binding(get: { acc.transparencyCustomized }, set: { x in
                        sysModel.change { sysModel.accommodations.setTransparency(customized: x, address: address) } }))
                    Group {
                        slider("Amplification", acc.transparencyAmplification) { sysModel.accommodations.setTransparency(amplification: $0, address: address) }
                        slider("Balance", acc.transparencyBalance) { sysModel.accommodations.setTransparency(balance: $0, address: address) }
                        slider("Tone", acc.transparencyTone, left: "Darker", right: "Brighter") { sysModel.accommodations.setTransparency(tone: $0, address: address) }
                        Toggle("Conversation Boost", isOn: Binding(get: { acc.conversationBoost }, set: { x in
                            sysModel.change { sysModel.accommodations.setTransparency(conversationBoost: x, address: address) } }))
                    }
                    .disabled(!acc.transparencyCustomized)
                    Text("Applies to the connected AirPods (\(address)) in Transparency mode.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Connect AirPods Pro (or other headphones with Transparency) as the output to customise it here.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Button("Open Accessibility ▸ Audio…") { SystemBackgroundSounds.openSystemSettings() }.controlSize(.small)
        }
        .onAppear { sysModel.startObserving { [weak model] in model?.activeDevice } }
        .onDisappear { sysModel.stopObserving() }
    }

    private func slider(_ title: String, _ value: Double, left: String = "", right: String = "",
                        set: @escaping (Double) -> Void) -> some View {
        ParamSlider(title: title, value: Binding(get: { value }, set: { x in sysModel.change { set(x) } }),
                    range: 0...1, step: 0.01, reset: 0.5) { v in
            !left.isEmpty && abs(v - 0.5) > 0.01 ? (v < 0.5 ? left : right) : "\(Int(v * 100))%"
        }
    }
}

/// 2-D pad for the Background Sounds tinnitus filter.
struct TinnitusPad: View {
    let x: Double, y: Double
    let frequency: Double, width: Double
    let onChange: (Double, Double) -> Void
    @Environment(\.theme) private var theme
    @State private var drag: CGPoint?
    @State private var lastSent = Date.distantPast

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let size = geo.size
                let px = drag.map { Double($0.x) } ?? x, py = drag.map { Double($0.y) } ?? y
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.08))
                    Path { p in
                        for i in 1..<4 {
                            let fx = size.width * CGFloat(i) / 4, fy = size.height * CGFloat(i) / 4
                            p.move(to: CGPoint(x: fx, y: 0)); p.addLine(to: CGPoint(x: fx, y: size.height))
                            p.move(to: CGPoint(x: 0, y: fy)); p.addLine(to: CGPoint(x: size.width, y: fy))
                        }
                    }
                    .stroke(.secondary.opacity(0.2))
                    Circle()
                        .fill(RadialGradient(colors: [theme.accent, theme.accent.opacity(0.2)], center: .center, startRadius: 2, endRadius: 22))
                        .frame(width: 28, height: 28)
                        .position(x: CGFloat((px + 1) / 2) * size.width, y: CGFloat(1 - (py + 1) / 2) * size.height)
                    VStack { Spacer(); HStack { Text("Low pitch"); Spacer(); Text("High pitch") } }
                        .font(.caption2).foregroundStyle(.secondary).padding(6)
                    VStack { HStack { Text("Wide"); Spacer() }; Spacer(); HStack { Text("Narrow"); Spacer() }.padding(.bottom, 14) }
                        .font(.caption2).foregroundStyle(.secondary).padding(6)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let nx = min(max(g.location.x / size.width * 2 - 1, -1), 1)
                        let ny = min(max((1 - g.location.y / size.height) * 2 - 1, -1), 1)
                        drag = CGPoint(x: nx, y: ny)
                        if Date().timeIntervalSince(lastSent) > 0.15 { lastSent = Date(); onChange(Double(nx), Double(ny)) }
                    }
                    .onEnded { _ in
                        if let d = drag { onChange(Double(d.x), Double(d.y)) }
                        drag = nil
                    })
            }
            .frame(height: 160)
            HStack {
                Text("Centre ≈ \(Self.hz(frequency))").font(.caption.monospacedDigit())
                Spacer()
                Text(String(format: "Width %.2f oct", width)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Button("Reset") { onChange(0, 0) }.controlSize(.mini)
            }
        }
    }

    static func hz(_ f: Double) -> String { f >= 1000 ? String(format: "%.1f kHz", f / 1000) : "\(Int(f)) Hz" }
}

/// Live "stops in mm:ss" for the Background Sounds timer.
struct TimerCountdown: View {
    let state: BackgroundSoundsState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            if let left = state.timerRemaining(nowReference: ctx.date.timeIntervalSinceReferenceDate) {
                Label("Stops in \(Self.format(left))", systemImage: "hourglass")
                    .font(.callout.monospacedDigit().bold())
            } else if state.timerEnabled, state.enabled {
                Label("Timer starts when sounds begin", systemImage: "hourglass").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    static func format(_ s: Double) -> String {
        let t = Int(s.rounded())
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }
}
