import EQCore
import SwiftUI

struct LoudnessPage: View {
    @EnvironmentObject var model: EQModel
    @Environment(\.theme) private var theme

    var body: some View {
        let l = $model.settings.features.leveler
        TwoColumns {
            Section2(title: "Levelling", icon: "speaker.wave.2.bubble") {
                ParamSlider(title: "Target", value: l.targetLUFS, range: -24...(-10), step: 0.5, reset: -16) {
                    String(format: "%.1f LUFS", $0)
                }
                ParamSlider(title: "Max boost", value: l.maxBoostDB, range: 0...12, step: 0.5, reset: 6) { String(format: "+%.1f dB", $0) }
                ParamSlider(title: "Max cut", value: l.maxCutDB, range: 0...20, step: 0.5, reset: 12) { String(format: "−%.1f dB", $0) }
                Picker("Speed", selection: l.speed) {
                    ForEach(LevelerSettings.Speed.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("−16 LUFS is a typical streaming level; −23 matches broadcast TV. Slow keeps dynamics most natural; fast reacts quickly to adverts and quiet videos.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        } right: {
            Section2(title: "Live", icon: "gauge.with.dots.needle.33percent") {
                TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                    let lufs = model.isRunning ? Double(model.backend.loudnessLUFS) : -120
                    let gain = model.isRunning ? Double(model.backend.levelerGainDB) : 0
                    HStack(alignment: .top, spacing: 32) {
                        stat(lufs > -70 ? String(format: "%.1f", lufs) : "—", "loudness (LUFS)")
                        stat(String(format: "%+.1f dB", gain), "levelling gain")
                    }
                }
                Text("Silence and very quiet passages are ignored, so fade-outs aren't pumped up.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
