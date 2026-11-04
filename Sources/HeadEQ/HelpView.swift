import AppKit
import SwiftUI

struct HelpTopic: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let body: [String]   // paragraphs; lines starting with "• " render as bullets
}

enum HelpContent {
    static let topics: [HelpTopic] = [
        HelpTopic(id: "start", title: "Getting started", icon: "play.circle", body: [
            "HeadEQ equalizes all sound your Mac plays — music, video, games, calls — before it reaches your headphones or speakers.",
            "• Turn it on with the Equalizer On/Off switch in the toolbar. When it's off, audio is completely untouched.",
            "• The first time it runs, macOS asks for permission to capture system audio. You can change this in System Settings ▸ Privacy & Security ▸ Screen & System Audio Recording.",
            "• Pick your headphones and a music preset on the Equalizer page. That's it.",
        ]),
        HelpTopic(id: "headphones", title: "Headphone profiles", icon: "headphones", body: [
            "A headphone profile corrects your headphones' own frequency response toward a neutral target, so presets sound the way they were meant to.",
            "• Auto-detect picks a profile from the connected device's name (e.g. “WH-1000XM3”).",
            "• Add by Name… searches the AutoEQ database of ~8,800 measured headphones and downloads the correction.",
            "• Customize… copies a built-in profile so you can edit its filters; New… starts from scratch. Edits are heard live.",
            "• The badge shows where a tuning comes from: Measured, Approximation, Generic, Yours or Modified. See Expert for details.",
        ]),
        HelpTopic(id: "presets", title: "Music presets & describing", icon: "music.note", body: [
            "Music presets are taste curves layered on top of the headphone correction.",
            "• Type a description such as “EDM on Bose SoundSport, more bass, less harsh” and press Create Preset. HeadEQ picks the headphones, a genre curve and tone tweaks.",
            "• Dragging a slider updates your own presets automatically; built-in presets become “Custom” until you Save As….",
            "• ↑/↓ nudge the focused band; double-click a slider to reset it. Use 0.1 dB steps for fine work.",
            "• Auto preamp lowers the overall gain so boosts never clip.",
        ]),
        HelpTopic(id: "output", title: "Output fine-tuning", icon: "dial.medium", body: [
            "• Output gain, balance, stereo width, mono, L/R swap and polarity invert.",
            "• Crossfeed blends a little of each channel into the other — great for old hard-panned recordings on headphones.",
            "• The peak limiter keeps the signal under its ceiling; the GR meter shows how hard it's working.",
            "• Device sample rate switches the hardware rate (useful for USB DACs).",
        ]),
        HelpTopic(id: "hearing", title: "Hearing protection", icon: "ear", body: [
            "Designed to be inaudible in normal listening.",
            "• Sudden loudness guard only reacts to jumps well above what you were just hearing (loud ads, notifications). Musical dynamics are left alone, and starting playback is never ducked.",
            "• Max listening level slowly rides the volume down if sustained loudness passes the ceiling.",
            "• Today's sound dose follows NIOSH guidance (85 dB for 8 hours, halving every +3 dB). Calibrate Sensitivity for your headphones for better estimates.",
            "These are estimates, not a medical measurement.",
        ]),
        HelpTopic(id: "system", title: "System audio & accommodations", icon: "speaker.wave.2", body: [
            "The System Audio page gathers relevant macOS settings in one place.",
            "• Device volume, mute and balance; alert volume; interface sounds, volume-change feedback and screen flash on alerts.",
            "• Headphone Accommodations (Apple and Beats headphones): tune for Balanced Tone, Vocal Range or Brightness and boost soft sounds.",
            "• Transparency mode customisation for connected AirPods Pro: amplification, balance, tone and Conversation Boost.",
            "These use the same settings as System Settings, so changes appear in both places.",
        ]),
        HelpTopic(id: "background", title: "Background Sounds", icon: "cloud.rain", body: [
            "Controls macOS's Accessibility Background Sounds: calming noise and nature sounds that mask distractions.",
            "• Choose a sound and volume, keep it playing under media at a separate volume, and stop it on lock or after a timer — the countdown shows time left.",
            "• Tinnitus EQ: drag the pad to match your tinnitus — left/right sets pitch (50 Hz–18 kHz), up/down sets how wide the filter is. Fine mode uses more bands; balance shifts it between ears.",
        ]),
        HelpTopic(id: "expert", title: "Expert & exporting", icon: "info.circle", body: [
            "• See who measured a correction, its target curve, a link to the source data and the exact filters.",
            "• See the complete signal chain in processing order.",
            "• Copy the EQ as Equalizer APO / AutoEQ ParametricEQ text to use in other apps.",
        ]),
        HelpTopic(id: "appearance", title: "Themes, icons & menu bar", icon: "paintpalette", body: [
            "Open HeadEQ ▸ Settings… (⌘,).",
            "• Pick a color theme, a Dock icon style (or match the theme), and whether HeadEQ appears in the Dock.",
            "• Choose the menu-bar icon, optionally show the current preset name, or hide the menu-bar icon.",
        ]),
        HelpTopic(id: "trouble", title: "Troubleshooting", icon: "wrench.and.screwdriver", body: [
            "• No sound / “Could not start”: check the audio-capture permission, then toggle the equalizer off and on.",
            "• Sound only in one app: make sure the output device is “System default” or the device you're listening on.",
            "• Bluetooth headphones sound worse during calls: that's the Bluetooth hands-free mode, not HeadEQ.",
            "• Background Sounds or Accommodations controls missing: your macOS version may have changed them — use the System Settings buttons.",
        ]),
    ]
}

struct HelpView: View {
    @State private var selection: HelpTopic? = HelpContent.topics.first
    @State private var search = ""

    private var filtered: [HelpTopic] {
        guard !search.isEmpty else { return HelpContent.topics }
        return HelpContent.topics.filter { t in
            t.title.localizedCaseInsensitiveContains(search) || t.body.contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(filtered, selection: $selection) { t in
                Label(t.title, systemImage: t.icon).tag(t)
            }
            .searchable(text: $search, placement: .sidebar, prompt: "Search help")
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            ScrollView {
                if let t = selection {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(t.title, systemImage: t.icon).font(.largeTitle.bold())
                        ForEach(t.body, id: \.self) { para in
                            if para.hasPrefix("• ") {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("•")
                                    Text(para.dropFirst(2))
                                }
                            } else {
                                Text(para)
                            }
                        }
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        Divider().padding(.vertical, 8)
                        Button("Open full documentation") { Self.openDocs() }
                    }
                    .padding(28)
                    .frame(maxWidth: 680, alignment: .leading)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    /// Opens the bundled user guide (copied into the app by build_app.sh).
    static func openDocs() {
        if let url = Bundle.main.url(forResource: "UserGuide", withExtension: "html", subdirectory: "docs")
            ?? Bundle.main.url(forResource: "UserGuide", withExtension: "md", subdirectory: "docs") {
            NSWorkspace.shared.open(url)
        }
    }
}
