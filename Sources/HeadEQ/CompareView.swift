import EQCore
import SwiftUI

struct ComparePage: View {
    @EnvironmentObject var model: EQModel
    @State private var blind: BlindTestSession?
    @State private var trials = 10

    var body: some View {
        TwoColumns {
            Section2(title: "Slots", icon: "square.on.square") {
                ForEach(ABSlot.allCases, id: \.self) { slot in slotRow(slot) }
                Toggle("Level-match A and B", isOn: Binding(get: { model.levelMatch }, set: { model.levelMatch = $0; model.play(model.audition) }))
                Text("Louder nearly always sounds better, so matching makes the comparison fair. It only ever turns the louder slot down.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section2(title: "Listen", icon: "ear") {
                Picker("Playing", selection: Binding(get: { model.audition?.rawValue ?? "live" },
                                                     set: { model.play($0 == "live" ? nil : ABSlot(rawValue: $0)) })) {
                    Text("Live settings").tag("live")
                    Text("A").tag("A").disabled(model.abSlots[.a] == nil)
                    Text("B").tag("B").disabled(model.abSlots[.b] == nil)
                }
                .pickerStyle(.segmented)
                HStack {
                    Button("A") { model.play(.a) }.keyboardShortcut("a", modifiers: [])
                    Button("B") { model.play(.b) }.keyboardShortcut("b", modifiers: [])
                    Button("Live") { model.play(nil) }.keyboardShortcut("l", modifiers: [])
                }
                .disabled(model.abSlots.count < 2)
                Text("Keys: A · B · L. Saved settings don't change while you compare.").font(.caption).foregroundStyle(.secondary)
            }
        } right: {
            Section2(title: "Blind test", icon: "eye.slash") {
                if model.abSlots.count < 2 {
                    Text("Capture both A and B to start a blind test.").foregroundStyle(.secondary)
                } else if var b = blind, !b.isFinished {
                    Text("Trial \(b.trialIndex + 1) of \(b.trials)").font(.title3.bold())
                    ProgressView(value: Double(b.trialIndex), total: Double(b.trials))
                    HStack {
                        Button("Play 1") { model.play(b.slot(forOption: 1)) }.keyboardShortcut("1", modifiers: [])
                        Button("Play 2") { model.play(b.slot(forOption: 2)) }.keyboardShortcut("2", modifiers: [])
                    }
                    Text("Which do you prefer?").font(.headline)
                    HStack {
                        Button("I prefer 1") { b.choose(option: 1); blind = b; next() }.buttonStyle(.borderedProminent)
                        Button("I prefer 2") { b.choose(option: 2); blind = b; next() }.buttonStyle(.borderedProminent)
                    }
                    Button("Cancel", role: .cancel) { blind = nil; model.play(nil) }.controlSize(.small)
                } else {
                    if let b = blind, b.isFinished {
                        Text("Result").font(.headline)
                        HStack(spacing: 24) {
                            stat("\(b.countA)", "chose A")
                            stat("\(b.countB)", "chose B")
                        }
                        Text(b.verdict).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                    Stepper("Trials: \(trials)", value: $trials, in: 5...30)
                    Button(blind == nil ? "Start blind test" : "Run again") {
                        blind = BlindTestSession(trials: trials)
                        model.play(blind?.slot(forOption: 1))
                    }
                    .buttonStyle(.borderedProminent)
                    Text("Each trial hides A and B behind 1 and 2 in random order. 8 of 10 or better means a real preference (p < 0.05).")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onDisappear { if blind == nil || blind!.isFinished { model.play(nil) } }
    }

    private func next() {
        if let b = blind, !b.isFinished { model.play(b.slot(forOption: 1)) } else { model.play(nil) }
    }

    private func slotRow(_ slot: ABSlot) -> some View {
        HStack {
            Text(slot.rawValue).font(.title2.bold()).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                if let s = model.abSlots[slot] {
                    Text(model.headphoneProfiles.first { $0.id == s.headphoneProfileID }?.name ?? "—").font(.callout)
                    Text((model.musicPresets.first { $0.id == s.musicPresetID }?.name ?? "Custom curve")
                         + (model.levelMatch && model.abSlots.count == 2 ? String(format: " · %+.1f dB match", model.levelOffset(for: slot)) : ""))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Empty").foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Capture current") { model.capture(slot) }.controlSize(.small)
        }
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading) {
            Text(v).font(.system(size: 28, weight: .bold, design: .rounded))
            Text(l).font(.caption).foregroundStyle(.secondary)
        }
    }
}
