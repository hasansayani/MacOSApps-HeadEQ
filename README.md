# HeadEQ

**Docs:** [User Guide](docs/UserGuide.md) · [Architecture & porting](docs/Architecture.md) · [Changelog](CHANGELOG.md) · current version in `VERSION`

System-wide equalizer for macOS (14.2+), with headphone-correction profiles and music presets.

## Build & run

```bash
./build_app.sh --open      # builds build/HeadEQ.app and launches it
swift test                 # runs EQCore unit tests
```

The first time it runs, macOS asks for permission to capture system audio. You can change this later in **System Settings → Privacy & Security → Screen & System Audio Recording**.

## How it works

1. A Core Audio **process tap** captures all system audio except HeadEQ's own, and mutes the original.
2. A private **aggregate device** (tap + your output device) runs HeadEQ's IO callback.
3. Audio passes through the headphone-correction filters, then the 10-band graphic EQ, then the preamp, then a soft clipper, and goes out to the device.
4. Turning the EQ off destroys the tap, so audio plays untouched with no added latency.

The two preset layers stack:
- **Headphones**: parametric corrections toward a Harman-style neutral target. These are auto-selected from the output device name (for example, "AirPods Pro" or "WH-1000XM5"). The model curves are approximations of published measurements. Fit and seal change the bass, so treat them as a starting point.
- **Music**: genre and taste curves on the graphic EQ. You can save your own presets.

**Auto preamp** lowers the gain by the peak boost of the combined curve, so the result never clips.

## Features

- **Describe it**: type something like *"EDM on Bose SoundSport, more bass, less harsh"*. HeadEQ picks the headphone profile and the genre curve, applies the tone changes, and saves the result as one of your presets, which you can keep editing.
  - **Recognised genres:** EDM, hip-hop, rock, pop, jazz, classical, acoustic, podcasts, gaming, movies.
  - **Recognised tone words:** more/less bass, bright/harsh, warm, vocals, workout.
- **Add headphones by name**: type a model, e.g. "Sennheiser Momentum 4". HeadEQ searches the open [AutoEQ](https://github.com/jaakkopasanen/AutoEq) database (about 8,800 measured corrections, cached for a week) and downloads the measured correction. If you're offline or the model isn't listed, it creates a starter profile based on the headphone type it guesses from the name.
- **Hearing protection** that stays out of the way during normal listening:
  - **Sudden-loudness guard:** only reacts to jumps of 10 dB or more above what you were just hearing. Musical dynamics are below that threshold, and pressing play after silence is never ducked.
  - **Max-level cap:** a slow volume ride on sustained loudness, so tone and transients are untouched.
  - **Daily dose meter:** follows NIOSH guidance (85 dB for 8 h, with a 3 dB exchange rate). Levels are estimated from the output level, the device volume and a headphone sensitivity you can calibrate. It warns you at 80% and lowers the cap when you pass 100%. It's an estimate, not a medical device.
- **Background Sounds (macOS Accessibility)**: control the system feature from HeadEQ and the menu bar:
  - On/off, choice of sound (Balanced, Bright and Dark Noise, Ocean, Rain, Stream, Night, Fire, Babble), and volume
  - Play-with-media toggle and its volume
  - Stop when locked, stop-after timer, and tinnitus filter

  It uses the same private settings object as System Settings (there's no public API), so changes stay in sync both ways. If a future macOS changes it, the card falls back to an "Open System Settings" button.
- **System Audio**: device volume, mute and balance; alert volume; UI sounds; volume-change feedback; screen flash on alerts; **Headphone Accommodations** (tone and boost); **AirPods Transparency** customisation.
- **Background Sounds EQ** (tinnitus pad: pitch × width, coarse/fine, ear balance) with a live stop-timer countdown.
- **App chrome**:
  - App icon and Dock icon styles, including one that matches the theme
  - Dock and menu-bar visibility, menu-bar icon choice and optional preset name (Settings ⌘,)
  - About window
  - Searchable Help (⌘?) and a bundled HTML User Guide
- **Expert: tuning sources**: for every headphone profile it shows:
  - Whether it's **measured** (and who measured it, plus a link to the data), an **approximation**, **generic**, **yours** or **modified**
  - The target curve
  - The exact filter table
  - Where the music curve came from, including the description it was generated from
  - The full signal chain

  You can copy any chain as Equalizer APO / AutoEQ text.
- **Custom headphones**: create profiles from scratch, or "Customize…" a built-in one. Each profile is a set of parametric filters (peak and shelf, with frequency, gain and Q), plus device-name keywords for auto-detect. You hear changes live while the editor is open.
- **Your presets**: Save As, Rename and Delete. Moving a slider updates the selected preset of your own automatically.
- **Visualizer**: shows the processed output as Bars, Spectrum or Wave, with the EQ curve drawn on top.
- **Themes**: Classic, Neon Rave, Synthwave, Ember, Sunset, Ocean, Forest, Graphite.
- **Output fine-tuning** (applied after the EQ, in this order):
  1. L/R swap
  2. Crossfeed (amount and cutoff)
  3. Stereo width or mono
  4. Balance
  5. Polarity invert
  6. Output gain
  7. Peak limiter (ceiling and release), with a gain-reduction meter

  The graphic EQ also has a bandwidth (Q) control, 0.5 or 0.1 dB slider steps, and ↑/↓ keys for fine adjustment. You can set the device's hardware sample rate (useful for USB DACs).

## Project layout (built for porting)

```
Sources/EQCore/    Portable core: pure Swift, no Apple frameworks (only libc math)
  Filter.swift       Biquad design (RBJ cookbook) + frequency response
  EQProcessor.swift  Real-time, allocation-free biquad cascade
  Presets.swift      Music presets, headphone profiles, device-name matching
  EQSettings.swift   Codable user state (sync-able across devices/platforms)
  OutputSettings.swift Post-EQ output stage parameters
  PresetGenerator.swift Description → preset (offline, rule-based)
  Spectrum.swift     Sample ring + pure-Swift FFT spectrum analyzer
  Themes.swift       Colour palettes as hex data (shared by every platform UI)
  AutoEQ.swift       AutoEQ index/ParametricEQ parsing, search, export, name→profile helpers
  TuningSource.swift Provenance of every tuning
  HearingProtection.swift Spike guard, level cap, exposure (dose) meter
  BackgroundSounds.swift Ambient-sound model + backend protocol (macOS drives the system feature)
  AudioBackend.swift Protocol each platform implements + OutputDevice model
Sources/HeadEQ/    macOS app: Core Audio tap backend + SwiftUI UI + menu bar
Tests/EQCoreTests/ DSP and preset tests
```

### Porting plan
| Platform | Backend to write | Notes |
|---|---|---|
| iOS / iPadOS | `AVAudioEngine` + `EQProcessor` in an `AVAudioSourceNode`/AU | iOS doesn't allow system-wide EQ: it only works for audio the app plays itself. The `EQCore` package links as-is. |
| Android | `DynamicsProcessing` (global session 0 or per-app sessions) | Swift-on-Android can reuse EQCore. A Kotlin port of `Filter.swift` + presets is also small. |
| Windows | WASAPI loopback + render, or an APO driver | EQCore builds with the Swift Windows toolchain. |
| Linux | PipeWire `filter-chain` node, or a PipeWire client | EQCore builds on Linux. |

Each platform implements `AudioBackend`. The settings, presets and DSP are shared.

## Roadmap: external DACs
Groundwork is already in place. The output picker lists every device, `OutputDevice.transport` identifies USB and Thunderbolt devices (flagged "DAC"), and multichannel outputs are handled (extra channels get silence). Next:
- Sample-rate and bit-depth selection per device (`kAudioDevicePropertyNominalSampleRate`, physical format)
- Bit-perfect bypass mode when the EQ is flat
- Per-device memory (remember the headphone profile and preset for each DAC UID)
- Hardware volume control and DAC-specific profiles (amp output impedance)
