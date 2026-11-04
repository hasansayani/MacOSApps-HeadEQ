import EQCore
import SwiftUI

struct DACPage: View {
    @EnvironmentObject var model: EQModel
    @State private var format: PhysicalFormat?

    var body: some View {
        let dac = $model.settings.features.dac
        let reasons = model.nonNeutralReasons
        TwoColumns {
            Section2(title: "Bit-perfect bypass", icon: "checkmark.seal") {
                Toggle("Bypass processing when nothing would change the sound", isOn: dac.bypassWhenNeutral)
                if model.isBypassed {
                    Label("Bypassing now: audio goes straight to the device, untouched.", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.teal)
                } else if reasons.isEmpty {
                    Label("The chain is neutral.", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                } else {
                    Text("Processing because of:").font(.callout.bold())
                    ForEach(reasons, id: \.self) { Label($0, systemImage: "circle.fill").font(.caption).foregroundStyle(.secondary) }
                    Text("Set these to neutral (or off) for bit-perfect playback.").font(.caption).foregroundStyle(.secondary)
                }
                Text("Bypass means HeadEQ steps out of the path completely, so apps reach the DAC exactly as they would without HeadEQ.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section2(title: "Sample rate for this device", icon: "metronome") {
                let rates = model.availableSampleRates
                let uid = model.activeDevice?.uid ?? ""
                Picker("Preferred rate", selection: Binding<Double>(
                    get: { model.settings.features.dac.preferredRates[uid] ?? 0 },
                    set: { model.setPreferredRate($0 == 0 ? nil : $0) })) {
                    Text("Don't change").tag(0.0)
                    ForEach(rates, id: \.self) { Text(String(format: "%g kHz", $0 / 1000)).tag($0) }
                }
                Toggle("Apply automatically when this device connects", isOn: dac.applyPreferredRate)
                Text("macOS uses one rate per device for all apps, so set this to match most of your music (44.1 kHz for CD-quality and most streaming, 48 kHz for video, higher for hi-res libraries).")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        } right: {
            Section2(title: "Device format", icon: "cpu") {
                if let d = model.activeDevice {
                    info("Device", d.name)
                    info("Connection", d.transport.rawValue + (d.isLikelyExternalDAC ? " · external DAC" : ""))
                    info("Nominal rate", String(format: "%g kHz", model.currentSampleRate / 1000))
                    info("Hardware format", format?.description ?? "—")
                    info("Output channels", "\(d.channels)")
                    info("Supported rates", model.availableSampleRates.map { String(format: "%g", $0 / 1000) }.joined(separator: ", ") + " kHz")
                } else {
                    Text("No output device").foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { format = model.physicalFormat() }
        .onChange(of: model.currentSampleRate) { _, _ in format = model.physicalFormat() }
    }

    private func info(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
            Text(value).textSelection(.enabled)
            Spacer()
        }
        .font(.callout)
    }
}
