import EQCore
import SwiftUI

struct BackgroundSoundsCard: View {
    @EnvironmentObject var bg: BackgroundSoundsModel

    private static let timerOptions: [(String, Double)] = [
        ("15 min", 900), ("30 min", 1800), ("45 min", 2700), ("1 hour", 3600),
        ("2 hours", 7200), ("4 hours", 14400), ("8 hours", 28800),
    ]

    private static let icons: [Int: String] = [
        1: "waveform", 2: "sun.max", 3: "moon", 4: "water.waves", 5: "cloud.rain",
        6: "drop", 7: "moon.stars", 8: "flame", 9: "person.2.wave.2",
    ]

    var body: some View {
        let st = bg.state
        Group {
            if !st.available {
                Section2(title: "Not available", icon: "exclamationmark.triangle") {
                    Text("Background Sounds controls aren't available on this macOS version.").foregroundStyle(.secondary)
                    Button("Open Accessibility ▸ Audio in System Settings") { SystemBackgroundSounds.openSystemSettings() }
                }
            } else {
                TwoColumns {
                    Section2(title: "Sound", icon: "speaker.wave.2") {
                        Toggle("Background Sounds", isOn: binding(\.enabled) { $0.setEnabled($1) }).toggleStyle(.switch)
                        Text("Calming noise or nature sounds to mask distractions and tinnitus. Controls the macOS Accessibility feature, so changes also show in System Settings.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 8)], spacing: 8) {
                            ForEach(bg.sounds) { sound in tile(sound, selected: st.selectedSoundID == sound.id) }
                        }
                        if let id = st.selectedSoundID, !bg.sounds.contains(where: { $0.id == id }) {
                            Text("Current sound was chosen in System Settings.").font(.caption).foregroundStyle(.secondary)
                        }
                        ParamSlider(title: "Volume", value: binding(\.volume) { $0.setVolume($1) },
                                    range: 0...1, step: 0.01, reset: 0.5) { "\(Int($0 * 100))%" }
                    }
                    .disabled(!st.enabled)
                    Section2(title: "With other audio", icon: "music.note.list") {
                        Toggle("Keep playing while media is playing", isOn: binding(\.playWithMedia) { $0.setPlayWithMedia($1) })
                        ParamSlider(title: "Volume", value: binding(\.mediaVolume) { $0.setMediaVolume($1) },
                                    range: 0...1, step: 0.01, reset: 0.2) { "\(Int($0 * 100))%" }
                            .disabled(!st.playWithMedia)
                            .help("Background Sounds volume while music or video is playing")
                    }
                    .disabled(!st.enabled)
                    Section2(title: "Schedule", icon: "timer") {
                        Toggle("Stop when Mac is locked", isOn: binding(\.stopOnLock) { $0.setStopOnLock($1) })
                        HStack {
                            Toggle("Stop after", isOn: Binding(get: { st.timerEnabled },
                                                               set: { on in bg.update { $0.setTimer(enabled: on, seconds: st.timerSeconds) } }))
                            Picker("", selection: Binding(get: { Self.nearestOption(st.timerSeconds) },
                                                          set: { secs in bg.update { $0.setTimer(enabled: st.timerEnabled, seconds: secs) } })) {
                                ForEach(Self.timerOptions, id: \.1) { Text($0.0).tag($0.1) }
                            }
                            .labelsHidden().fixedSize()
                            .disabled(!st.timerEnabled)
                        }
                        TimerCountdown(state: st)
                    }
                    .disabled(!st.enabled)
                    .disabled(!st.enabled)
                } right: {
                    Section2(title: "Background Sounds EQ (tinnitus filter)", icon: "ear.badge.waveform") {
                        Toggle("Shape sounds to match my tinnitus", isOn: binding(\.tinnitusFilterEnabled) { $0.setTinnitusFilter($1) })
                        Group {
                            TinnitusPad(x: st.tinnitusX, y: st.tinnitusY, frequency: st.tinnitusFrequency, width: st.tinnitusWidth) { x, y in
                                bg.update { $0.setTinnitusPoint(x: x, y: y) }
                            }
                            Picker("Filter", selection: binding(\.tinnitusFine) { $0.setTinnitusFine($1) }) {
                                Text("Coarse").tag(false)
                                Text("Fine").tag(true)
                            }
                            .pickerStyle(.segmented)
                            ParamSlider(title: "Ear balance", value: binding(\.tinnitusBalance) { $0.setTinnitusBalance($1) },
                                        range: -1...1, step: 0.01, reset: 0) { v in
                                abs(v) < 0.005 ? "Both" : String(format: "%@ %d%%", v < 0 ? "L" : "R", Int(abs(v) * 100))
                            }
                        }
                        .disabled(!st.tinnitusFilterEnabled)
                        Text("Drag across to match the pitch of your tinnitus, up/down for how wide the filter is.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .disabled(!st.enabled)
                    Text("Background Sounds play through the system, so HeadEQ's EQ and hearing protection apply to them too.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { bg.startObserving() }
        .onDisappear { bg.stopObserving() }
    }

    private func tile(_ sound: BackgroundSound, selected: Bool) -> some View {
        Button { bg.update { $0.select(sound) } } label: {
            VStack(spacing: 6) {
                Image(systemName: Self.icons[sound.group] ?? "speaker.wave.2").font(.title2)
                Text(sound.name).font(.caption).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.accentColor : .clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func binding<T>(_ key: KeyPath<BackgroundSoundsState, T>,
                            set: @escaping (BackgroundSoundsBackend, T) -> Void) -> Binding<T> {
        Binding(get: { bg.state[keyPath: key] }, set: { v in bg.update { set($0, v) } })
    }

    private static func nearestOption(_ seconds: Double) -> Double {
        timerOptions.min { abs($0.1 - seconds) < abs($1.1 - seconds) }!.1
    }
}

/// Compact menu-bar controls.
struct BackgroundSoundsMenu: View {
    @EnvironmentObject var bg: BackgroundSoundsModel

    var body: some View {
        if bg.state.available {
            Menu("Background Sounds: \(bg.state.enabled ? (bg.sounds.first { $0.id == bg.state.selectedSoundID }?.name ?? "On") : "Off")") {
                Toggle("On", isOn: Binding(get: { bg.state.enabled }, set: { v in bg.update { $0.setEnabled(v) } }))
                Divider()
                ForEach(bg.sounds) { s in
                    Button((bg.state.selectedSoundID == s.id ? "✓ " : "    ") + s.name) {
                        bg.update { $0.select(s); $0.setEnabled(true) }
                    }
                }
                if let left = bg.state.timerRemaining(nowReference: Date().timeIntervalSinceReferenceDate) {
                    Text("Stops in \(TimerCountdown.format(left))")
                }
                Divider()
                ForEach([("Volume 25%", 0.25), ("Volume 50%", 0.5), ("Volume 75%", 0.75), ("Volume 100%", 1.0)], id: \.1) { label, v in
                    Button(label) { bg.update { $0.setVolume(v) } }
                }
            }
        }
    }
}
