import EQCore
import SwiftUI

struct HearingProtectionCard: View {
    @EnvironmentObject var model: EQModel
    @Environment(\.theme) private var theme

    var body: some View { Inner(meters: model.meters) }

    private struct Inner: View {
    @EnvironmentObject var model: EQModel
    @ObservedObject var meters: LiveMeters
    @Environment(\.theme) private var theme

    var body: some View {
        let h = $model.settings.hearing
        let hs = model.settings.hearing
        TwoColumns {
            Section2(title: "Protection", icon: "shield.lefthalf.filled") {
                Toggle("Protect my hearing", isOn: h.enabled).toggleStyle(.switch)
                Text("Works silently in the background. Normal music dynamics and tone are untouched; it only steps in for sudden blasts or long, very loud listening.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section2(title: "Sudden loudness guard", icon: "bolt.badge.clock") {
                Toggle("Catch abrupt jumps (loud ads, notifications, a much louder track)", isOn: h.spikeGuard)
                ParamSlider(title: "Trigger at", value: h.spikeThresholdDB, range: 6...20, step: 1, reset: 10) {
                    "+\(Int($0)) dB"
                }
                .disabled(!hs.spikeGuard)
            }
            .disabled(!hs.enabled)
            Section2(title: "Max listening level", icon: "speaker.wave.3") {
                Toggle("Slowly ride the volume down if sustained loudness exceeds the ceiling", isOn: h.levelCap)
                ParamSlider(title: "Ceiling", value: h.maxLevelSPL, range: 75...105, step: 1, reset: 90) {
                    "\(Int($0)) dB"
                }
                .disabled(!hs.levelCap)
                ParamSlider(title: "Sensitivity", value: h.sensitivitySPL, range: 85...120, step: 1, reset: 100) {
                    "\(Int($0)) dB"
                }
                .help("Loudness (dB SPL) your headphones produce from a full-scale signal at max volume. Typical: 95–110. Raise it if levels read too low.")
                Text("Sensitivity calibrates the dB estimates for your headphones (typical 95–110).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(!hs.enabled)
        } right: {
            Section2(title: "Right now", icon: "gauge.with.dots.needle.50percent") {
                HStack(alignment: .top, spacing: 32) {
                    stat(meters.estimatedSPL.map { "\(Int($0.rounded())) dB" } ?? "—", "estimated level",
                         color: levelColor(meters.estimatedSPL ?? 0))
                    stat(meters.protectionReductionDB < -0.5 ? String(format: "%.1f dB", meters.protectionReductionDB) : "Idle",
                         "protection gain reduction")
                }
                Text("Device volume: \(meters.deviceVolumeDB.map { String(format: "%.0f dB", $0) } ?? "n/a")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section2(title: "Today's sound dose", icon: "calendar.badge.clock") {
                ProgressView(value: min(meters.exposure.dose, 1))
                    .tint(meters.doseLevel == .ok ? theme.accent : meters.doseLevel == .high ? .orange : .red)
                HStack {
                    Text("\(Int((meters.exposure.dose * 100).rounded()))% of daily safe limit")
                        .font(.title3.bold()).monospacedDigit()
                    Spacer()
                    Button("Reset") { model.resetExposure() }.controlSize(.small)
                }
                Text("Listened \(duration(meters.exposure.listeningSeconds))").font(.callout)
                if let spl = meters.estimatedSPL, let left = meters.exposure.remainingSeconds(atSPL: spl) {
                    Text("≈ \(duration(left)) left at the current level").font(.callout).foregroundStyle(.secondary)
                }
                Divider()
                Toggle("Warn me at 80% and 100%", isOn: h.doseWarnings)
                ParamSlider(title: "Over 100%", value: h.overDoseCapReductionDB, range: 0...12, step: 1, reset: 5) {
                    $0 == 0 ? "No change" : "−\(Int($0)) dB cap"
                }
                Text("Based on NIOSH guidance: 85 dB for 8 h, halving every +3 dB. Estimate only, not a medical device. Audio isn't measured while the EQ is off.")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .disabled(!hs.enabled)
        }
    }

    private func stat(_ value: String, _ label: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func levelColor(_ spl: Double) -> Color {
        spl >= 90 ? .red : spl >= 80 ? .orange : .primary
    }

    private func duration(_ seconds: Double) -> String {
        let m = Int(seconds / 60)
        return m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min"
    }
    }
}

/// Banner shown at the top of the window when today's dose is high.
struct DoseBanner: View {
    @EnvironmentObject var model: EQModel

    var body: some View { Inner(meters: model.meters) }

    private struct Inner: View {
    @EnvironmentObject var model: EQModel
    @ObservedObject var meters: LiveMeters

    var body: some View {
        if model.settings.hearing.enabled, model.settings.hearing.doseWarnings, meters.doseLevel != .ok {
            let over = meters.doseLevel == .over
            HStack(spacing: 10) {
                Image(systemName: over ? "ear.trianglebadge.exclamationmark" : "ear.badge.waveform")
                Text(over
                     ? "You've reached today's safe listening dose\(model.settings.hearing.overDoseCapReductionDB > 0 ? " — max level lowered by \(Int(model.settings.hearing.overDoseCapReductionDB)) dB" : ""). Consider a break or lower volume."
                     : "You've used \(Int(meters.exposure.dose * 100))% of today's safe listening dose.")
                    .font(.callout)
                Spacer()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill((over ? Color.red : Color.orange).opacity(0.18)))
        }
    }
}
}
