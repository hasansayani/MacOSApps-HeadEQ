import AVFoundation
import EQCore
import SwiftUI

/// Plays test tones straight to the output device. HeadEQ's own process is
/// excluded from the system tap, so tones are never equalized. The engine
/// only exists while a test is running.
final class TonePlayer {
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!

    func start() throws {
        guard engine == nil else { return }
        let e = AVAudioEngine(), p = AVAudioPlayerNode()
        e.attach(p)
        e.connect(p, to: e.mainMixerNode, format: format)
        e.mainMixerNode.outputVolume = 1
        try e.start()
        p.play()
        engine = e; player = p
    }

    func stop() {
        player?.stop(); engine?.stop()
        player = nil; engine = nil
    }

    /// Three 300 ms pulses with 25 ms ramps, in one ear.
    func play(frequency: Double, levelDBFS: Double, ear: Ear) {
        guard let player else { return }
        let sr = format.sampleRate
        let pulse = Int(0.3 * sr), gap = Int(0.2 * sr), ramp = Int(0.025 * sr)
        let total = 3 * pulse + 2 * gap
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total)) else { return }
        buf.frameLength = AVAudioFrameCount(total)
        let amp = Float(pow(10, levelDBFS / 20))
        let l = buf.floatChannelData![0], r = buf.floatChannelData![1]
        for i in 0..<total {
            let inPulse = i % (pulse + gap)
            var env: Float = 0
            if inPulse < pulse {
                env = Float(min(1, Double(min(inPulse, pulse - inPulse)) / Double(ramp)))
            }
            let s = amp * env * Float(sin(2 * Double.pi * frequency * Double(i) / sr))
            l[i] = ear == .left ? s : 0
            r[i] = ear == .right ? s : 0
        }
        player.scheduleBuffer(buf, at: nil, options: .interrupts)
    }
}

@MainActor
final class HearingTestController: ObservableObject {
    enum Phase: Equatable { case idle, running, finished }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var session = HearingTestSession()
    @Published private(set) var error: String?
    private let tones = TonePlayer()
    private var pending: DispatchWorkItem?

    var current: HearingTestSession.Presentation? { session.current }

    func start(ears: [Ear]) {
        do { try tones.start() } catch { self.error = "Couldn't start audio: \(error.localizedDescription)"; return }
        error = nil
        session = HearingTestSession(ears: ears)
        phase = .running
        scheduleTone(after: 0.8)
    }

    func respond(heard: Bool, onFinish: (Audiogram) -> Void) {
        guard phase == .running else { return }
        session.respond(heard: heard)
        if session.isFinished {
            phase = .finished
            tones.stop()
            var a = session.audiogram
            a.takenOn = ISO8601DateFormatter().string(from: Date())
            onFinish(a)
        } else {
            // Random pause so you can't anticipate the next tone.
            scheduleTone(after: Double.random(in: 0.7...1.6))
        }
    }

    func replay() { scheduleTone(after: 0.1) }

    func stop() {
        pending?.cancel()
        tones.stop()
        phase = .idle
    }

    private func scheduleTone(after delay: Double) {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, let p = self.session.current else { return }
            self.tones.play(frequency: p.frequency, levelDBFS: p.levelDBFS, ear: p.ear)
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}

struct HearingTestPage: View {
    @EnvironmentObject var model: EQModel
    @StateObject private var test = HearingTestController()
    @Environment(\.theme) private var theme

    var body: some View {
        let p = $model.settings.features.personal
        let personal = model.settings.features.personal
        TwoColumns {
            Section2(title: "Hearing test", icon: "waveform.and.person.filled") {
                switch test.phase {
                case .idle, .finished:
                    VStack(alignment: .leading, spacing: 8) {
                        if test.phase == .finished {
                            Label("Test complete. Your correction is applied.", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                        }
                        Text("Takes about 5 minutes. Use the headphones you'll listen with, in a quiet room.")
                        Label("Set the volume to a comfortable level (about 50%) and don't change it during the test.", systemImage: "speaker.wave.2")
                        Label("You'll hear 3 short beeps in one ear. Answer whether you heard them, even if they were very faint.", systemImage: "ear")
                        Label("Not a medical test. See an audiologist if you have concerns about your hearing.", systemImage: "cross.case")
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    HStack {
                        Button("Test both ears") { test.start(ears: [.left, .right]) }.buttonStyle(.borderedProminent)
                        Button("Left only") { test.start(ears: [.left]) }
                        Button("Right only") { test.start(ears: [.right]) }
                    }
                    if let e = test.error { Text(e).foregroundStyle(.orange).font(.caption) }
                case .running:
                    if let c = test.current {
                        Text("\(c.ear.title) ear · \(TinnitusPad.hz(c.frequency))").font(.title2.bold())
                        ProgressView(value: test.session.progress)
                        Text("Did you hear the beeps?").font(.headline).padding(.top, 6)
                        HStack(spacing: 12) {
                            Button { test.respond(heard: true) { save($0) } } label: {
                                Label("I heard it", systemImage: "checkmark").frame(maxWidth: .infinity, minHeight: 36)
                            }
                            .buttonStyle(.borderedProminent).keyboardShortcut(.space, modifiers: [])
                            Button { test.respond(heard: false) { save($0) } } label: {
                                Label("Nothing", systemImage: "xmark").frame(maxWidth: .infinity, minHeight: 36)
                            }
                            .keyboardShortcut("n", modifiers: [])
                        }
                        HStack {
                            Button("Play again") { test.replay() }
                            Spacer()
                            Button("Stop test", role: .cancel) { test.stop() }
                        }
                        Text("Keyboard: Space = heard · N = nothing").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section2(title: "Correction", icon: "slider.horizontal.below.square.filled.and.square") {
                ParamSlider(title: "Strength", value: p.strength, range: 0...1, step: 0.05, reset: 0.5) { "\(Int($0 * 100))%" }
                ParamSlider(title: "Max boost", value: p.maxBoostDB, range: 0...15, step: 0.5, reset: 10) { String(format: "+%.1f dB", $0) }
                Text("50% follows the classic half-gain rule: restore half of each relative loss. The correction is made per ear and is clip-safe.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if personal.audiogram != nil {
                    Button("Clear test results", role: .destructive) { model.settings.features.personal.audiogram = nil }.controlSize(.small)
                }
            }
            .disabled(personal.audiogram == nil)
        } right: {
            Section2(title: "Your results", icon: "chart.xyaxis.line") {
                if let a = personal.audiogram {
                    AudiogramChart(audiogram: a).frame(height: 220)
                    HStack(spacing: 16) {
                        Label("Left", systemImage: "xmark").foregroundStyle(.blue)
                        Label("Right", systemImage: "circle").foregroundStyle(.red)
                        Spacer()
                        if !a.takenOn.isEmpty { Text("Taken \(String(a.takenOn.prefix(10)))").font(.caption).foregroundStyle(.secondary) }
                    }
                    .font(.caption)
                    Text("Relative to your best threshold. Lower on the chart means you need more level at that pitch.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Take the test to see your results and get a personal correction.").foregroundStyle(.secondary)
                }
            }
            if personal.audiogram != nil {
                Section2(title: "Correction curves", icon: "waveform.path") {
                    ZStack {
                        ResponseCurveView(filters: personal.filters(.left), preamp: 0).environment(\.theme, AppTheme.named("ocean"))
                        ResponseCurveView(filters: personal.filters(.right), preamp: 0).environment(\.theme, AppTheme.named("ember"))
                    }
                    .frame(height: 140)
                    HStack {
                        Text("Left").foregroundStyle(Color(hex: "#00B4D8"))
                        Text("Right").foregroundStyle(Color(hex: "#FF9F1C"))
                    }
                    .font(.caption)
                }
            }
        }
        .onDisappear { test.stop() }
    }

    private func save(_ a: Audiogram) {
        model.settings.features.personal.audiogram = a
    }
}

struct AudiogramChart: View {
    let audiogram: Audiogram

    var body: some View {
        Canvas { ctx, size in
            let loss: [Ear: [(Double, Double)]] = [.left: audiogram.relativeLoss(.left), .right: audiogram.relativeLoss(.right)]
            let maxLoss = max(30, (loss.values.flatMap { $0.map(\.1) }.max() ?? 0) + 5)
            func x(_ f: Double) -> CGFloat { CGFloat(log2(f / 200) / log2(10000 / 200)) * (size.width - 30) + 24 }
            func y(_ l: Double) -> CGFloat { CGFloat(l / maxLoss) * (size.height - 24) + 8 }
            var grid = Path()
            for f in HearingTestSession.frequencies {
                grid.move(to: CGPoint(x: x(f), y: 0)); grid.addLine(to: CGPoint(x: x(f), y: size.height - 14))
                ctx.draw(Text(TinnitusPad.hz(f)).font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: x(f), y: size.height - 6))
            }
            for l in stride(from: 0.0, through: maxLoss, by: 10) {
                grid.move(to: CGPoint(x: 20, y: y(l))); grid.addLine(to: CGPoint(x: size.width, y: y(l)))
                ctx.draw(Text("\(Int(l))").font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: 10, y: y(l)))
            }
            ctx.stroke(grid, with: .color(.secondary.opacity(0.2)))
            for (ear, color) in [(Ear.left, Color.blue), (Ear.right, Color.red)] {
                let pts = (loss[ear] ?? []).map { CGPoint(x: x($0.0), y: y($0.1)) }
                guard !pts.isEmpty else { continue }
                var line = Path(); line.addLines(pts)
                ctx.stroke(line, with: .color(color.opacity(0.8)), lineWidth: 1.5)
                for p in pts {
                    if ear == .left {
                        var m = Path()
                        m.move(to: CGPoint(x: p.x - 4, y: p.y - 4)); m.addLine(to: CGPoint(x: p.x + 4, y: p.y + 4))
                        m.move(to: CGPoint(x: p.x + 4, y: p.y - 4)); m.addLine(to: CGPoint(x: p.x - 4, y: p.y + 4))
                        ctx.stroke(m, with: .color(color), lineWidth: 2)
                    } else {
                        ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9)), with: .color(color), lineWidth: 2)
                    }
                }
            }
        }
    }
}
