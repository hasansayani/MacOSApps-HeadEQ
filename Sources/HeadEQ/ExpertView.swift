import AppKit
import EQCore
import SwiftUI

/// Expert options: where every tuning comes from, the exact filters, and the
/// full signal chain — with export to Equalizer APO / AutoEQ format.
struct ExpertView: View {
    @EnvironmentObject var model: EQModel
    @Environment(\.theme) private var theme
    @State private var copied: String?

    var body: some View {
        let hp = model.headphoneProfile
        let src = hp.provenance
        TwoColumns {
            // Headphone correction provenance
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(hp.name).font(.headline)
                        Badge(text: src.title, color: badgeColor(src.kind))
                        Spacer()
                        if let url = src.url.flatMap(URL.init(string:)) {
                            Link(destination: url) { Label("View source data", systemImage: "arrow.up.right.square") }
                        }
                    }
                    Text(src.summary).font(.callout)
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                        info("Measured by", src.measuredBy)
                        info("Database", src.database)
                        info("Target curve", src.target)
                        info("Based on", src.basedOn)
                        info("Type", hp.kind.rawValue)
                        info("Auto-detect keywords", hp.matchKeywords.isEmpty ? nil : hp.matchKeywords.joined(separator: ", "))
                        info("Notes", hp.note.isEmpty ? nil : hp.note)
                    }
                    .font(.callout)
                    if src.kind == .approximation {
                        Text("Tip: for a measured version, use Headphones ▸ Add by Name… and pick this model from AutoEQ.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    FilterTable(filters: hp.filters)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Headphone correction — tuning source", systemImage: "headphones")
            }

        } right: {
            // Music curve provenance
            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.currentMusicPreset?.name ?? "Custom (unsaved)").font(.headline)
                    Text(model.currentMusicPreset?.originDescription ?? "Manual slider adjustments, not saved as a preset")
                        .font(.callout)
                    Text(zip(GraphicEQ.frequencies, model.settings.bandGains)
                        .map { "\(GraphicEQ.label($0)): \(String(format: "%+.1f", $1))" }.joined(separator: "   "))
                        .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    Text("Peaking filters, Q \(String(format: "%.2f", model.settings.graphicQ)).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Music curve — origin", systemImage: "music.note")
            }

            // Signal chain
            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(chainSteps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(i + 1).").monospacedDigit().foregroundStyle(.secondary).frame(width: 22, alignment: .trailing)
                            Text(step.0).bold()
                            Text(step.1).foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                    Text("Sample rate \(String(format: "%.1f", model.backend.sampleRate / 1000)) kHz · 32-bit float processing · biquads per RBJ Audio EQ Cookbook · \(model.filters.count) filters total")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Signal chain", systemImage: "point.3.connected.trianglepath.dotted")
            }

            HStack {
                Button("Copy full EQ (Equalizer APO / AutoEQ format)") {
                    copy(AutoEQ.exportParametricEQ(filters: model.filters, preamp: model.effectivePreamp), "full EQ")
                }
                Button("Copy headphone correction only") {
                    let pre = -max(0, FrequencyResponse.peakGain(filters: hp.filters))
                    copy(AutoEQ.exportParametricEQ(filters: hp.filters, preamp: pre), "headphone correction")
                }
                if let copied { Text("Copied \(copied)").font(.caption).foregroundStyle(.secondary) }
            }
            .controlSize(.small)
        }
    }

    private var chainSteps: [(String, String)] {
        let s = model.settings, o = s.output, h = s.hearing
        var steps: [(String, String)] = [
            ("Preamp", String(format: "%+.1f dB%@", model.effectivePreamp, s.autoPreamp ? " (auto, clip-safe)" : "")),
            ("Headphone correction", "\(model.headphoneProfile.filters.count) parametric filters — \(model.headphoneProfile.provenance.title.lowercased())"),
            ("Graphic EQ", "10 bands, Q \(String(format: "%.2f", s.graphicQ))"),
        ]
        var out: [String] = []
        if o.swapChannels { out.append("L/R swap") }
        if o.crossfeed > 0 { out.append("crossfeed \(Int(o.crossfeed * 100))% @ \(Int(o.crossfeedCutoff)) Hz") }
        if o.mono { out.append("mono") } else if o.width != 1 { out.append("width \(Int(o.width * 100))%") }
        if o.balance != 0 { out.append(String(format: "balance %+.0f%%", o.balance * 100)) }
        if o.invertPolarity { out.append("polarity inverted") }
        if o.gainDB != 0 { out.append(String(format: "gain %+.1f dB", o.gainDB)) }
        steps.append(("Output stage", out.isEmpty ? "neutral" : out.joined(separator: ", ")))
        steps.append(("Hearing protection", !h.enabled ? "off" :
            [h.spikeGuard ? "spike guard +\(Int(h.spikeThresholdDB)) dB" : nil,
             h.levelCap ? "level cap \(Int(h.maxLevelSPL)) dB SPL (est.)" : nil].compactMap { $0 }.joined(separator: ", ")))
        steps.append(("Peak limiter", o.limiterEnabled ? String(format: "ceiling %.1f dBFS, release %d ms", o.limiterCeilingDB, Int(o.limiterReleaseMS)) : "off (hard clip at 0 dBFS)"))
        return steps
    }

    @ViewBuilder
    private func info(_ label: String, _ value: String?) -> some View {
        if let value {
            GridRow {
                Text(label).foregroundStyle(.secondary)
                Text(value).textSelection(.enabled)
            }
        }
    }

    private func badgeColor(_ kind: TuningSource.Kind) -> Color {
        switch kind {
        case .measured: return .green
        case .approximation: return .orange
        case .generic: return .gray
        case .userCreated, .modified: return theme.accent
        }
    }

    private func copy(_ text: String, _ what: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = what
    }
}

struct Badge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(.caption.bold())
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.2)))
            .foregroundStyle(color)
    }
}

struct FilterTable: View {
    let filters: [FilterSpec]

    var body: some View {
        if filters.isEmpty {
            Text("No correction filters.").font(.caption).foregroundStyle(.secondary)
        } else {
            Grid(alignment: .trailing, horizontalSpacing: 18, verticalSpacing: 2) {
                GridRow {
                    Text("#"); Text("Type").gridColumnAlignment(.leading); Text("Freq"); Text("Gain"); Text("Q")
                }
                .font(.caption.bold()).foregroundStyle(.secondary)
                ForEach(Array(filters.enumerated()), id: \.offset) { i, f in
                    GridRow {
                        Text("\(i + 1)")
                        Text(f.type == .peak ? "Peak" : f.type == .lowShelf ? "Low shelf" : "High shelf")
                        Text("\(Int(f.frequency)) Hz")
                        Text(String(format: "%+.1f dB", f.gain))
                        Text(String(format: "%.2f", f.q))
                    }
                    .font(.caption.monospacedDigit())
                }
            }
            .textSelection(.enabled)
        }
    }
}
