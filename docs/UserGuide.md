# HeadEQ User Guide

HeadEQ equalizes all sound your Mac plays — before it reaches your headphones or speakers — and tunes it for the exact headphones you're wearing.

## Getting started

1. Open HeadEQ. The first time, macOS asks to let it capture system audio — click **Allow**. (Change later in System Settings ▸ Privacy & Security ▸ Screen & System Audio Recording.)
2. Flip the **Equalizer On/Off** switch in the toolbar to *On*.
3. On the **Equalizer** page choose your **Headphones** and a **Music** preset.

When the equalizer is *Off*, audio is completely untouched — no processing, no added latency.

## The window

The sidebar has pages; every page uses two columns:

| Page | What's there |
|---|---|
| Equalizer | Describe-a-preset, headphones, music presets, visualizer, graphic EQ |
| Output | Gain, balance, stereo width, mono/swap/polarity, crossfeed, peak limiter, device sample rate |
| System Audio | Device volume/mute/balance, alerts & interface sounds, Headphone Accommodations, AirPods Transparency |
| Hearing Protection | Sudden loudness guard, max listening level, today's sound dose |
| Background Sounds | macOS Background Sounds: sound, volume, timer with countdown, tinnitus EQ |
| Expert | Where each tuning comes from, exact filters, full signal chain, export |

The toolbar (on every page) holds the output device, color theme and the master switch.

## Headphones

A headphone profile corrects your headphones' own frequency response toward a neutral target, so every preset sounds as intended.

- **Auto-detect** chooses a profile from the connected device's name.
- **Add by Name…** — type a model (e.g. *Sennheiser Momentum 4*). HeadEQ searches the open AutoEQ database (~8,800 measured headphones) and downloads its correction. Offline or not listed? **Create starter profile** guesses the type from the name.
- **Customize…** copies a built-in profile for editing; **New…** starts blank. The editor plays your changes live.
- The badge shows the tuning's source: **Measured**, **Approximation**, **Generic**, **Yours** or **Modified**.

## Music presets

- **Describe it**: type *"EDM on Bose SoundSport, more bass, less harsh"* and press **Create Preset**.
- Drag sliders to tweak. Your own presets save automatically; built-ins become *Custom* until you **Save As…**.
- Keyboard: focus a band and press ↑/↓. Double-click a slider to reset it. Choose 0.1 dB steps for precision.
- **Bandwidth Q** makes bands narrower or wider. **Auto preamp** prevents clipping.

## Output fine-tuning

- **Output gain**, **Balance**, **Stereo width** (0–200 %), **Mono**, **Swap L/R**, **Invert polarity**.
- **Crossfeed** mixes a little of each channel into the other — less fatiguing for hard-panned recordings.
- **Peak limiter** with ceiling and release; the *GR* meter shows gain reduction.
- **Device sample rate** for DACs and interfaces.

## System Audio

- **Output device**: hardware volume, mute and balance.
- **Alerts & interface sounds**: alert volume, UI sound effects, volume-change feedback, screen flash on alert.
- **Headphone Accommodations** (Apple/Beats headphones): *Tune audio for* Balanced Tone, Vocal Range or Brightness, and *Boost soft sounds* Slight/Moderate/Strong.
- **Transparency mode** for the connected AirPods Pro: amplification, balance, tone and Conversation Boost.

These are the same settings as System Settings — changes show up in both.

## Hearing protection

Built to stay out of the way:

- **Sudden loudness guard** reacts only to abrupt jumps well above what you were just hearing (loud ads, notifications). Song dynamics are left alone and pressing *play* is never ducked.
- **Max listening level** slowly lowers the volume if sustained loudness passes the ceiling. Tone and transients are untouched.
- **Today's sound dose** follows NIOSH guidance — 85 dB for 8 hours, halving for every +3 dB. HeadEQ warns at 80 % and can lower the ceiling after 100 %.
- **Sensitivity** calibrates the estimates for your headphones (typical 95–110 dB).

> Levels and dose are estimates, not a medical measurement. Audio isn't measured while the equalizer is off.

## Background Sounds

Controls macOS's Accessibility Background Sounds.

- Choose **Balanced/Bright/Dark Noise, Ocean, Rain, Stream, Night, Fire** or **Babble**, and set the volume.
- **Keep playing while media is playing**, at its own volume.
- **Stop when Mac is locked** or **Stop after** a time — the countdown shows what's left.
- **Background Sounds EQ (tinnitus filter)**: drag across the pad to match the pitch of your tinnitus and up/down for the filter width; choose Coarse or Fine and shift the balance between ears.

## Expert

- Provenance of the active headphone correction: who measured it, the database, the target curve and a link to the source data.
- The exact filters (type, frequency, gain, Q), the music curve's origin and the whole signal chain in processing order.
- **Copy** the EQ as Equalizer APO / AutoEQ *ParametricEQ* text.

## Optional features

The **Features** page lists every optional feature with an on/off switch and what it costs. When a feature is off it uses no processing and no memory. Each feature's page also has its switch at the top.

| Feature | Page | What it does |
|---|---|---|
| Measured headphone profiles | Equalizer | Real AutoEQ measurements for all built-in models (on by default) |
| Per-device memory | Output | Each device keeps its own profile, preset and output settings |
| Virtual surround | Spatial | Speaker simulation: interaural delay, head shadow, room reflections |
| Volume levelling | Loudness | Evens out loudness (LUFS, ITU BS.1770) without squashing dynamics |
| Hearing test & personal correction | Hearing Test | Per-ear tone test and a gentle per-ear correction |
| DAC mode | DAC Mode | Bit-perfect bypass when neutral; preferred sample rate per device |
| A/B & blind comparison | Compare | Instant, level-matched switching and blind preference tests |
| Preset sync | Library & Sync | Sync presets and headphones through iCloud Drive or any folder |
| Launch at login, update checks | Settings ▸ General | Start with your Mac; daily check for new versions |

### Hearing test

Use your usual headphones in a quiet room with the volume around 50 %, and don't change the volume during the test. Press **Space** when you hear the three beeps and **N** when you don't. Results are relative to your best threshold; *Strength* 50 % applies the classic half-gain rule. This is not a medical test.

### DAC mode

When nothing in the chain changes the sound, HeadEQ steps out of the audio path entirely, so apps reach your DAC bit-perfect. The DAC page lists exactly what's preventing bypass. You can also remember a hardware sample rate per device.

### Library & Sync

Export and import `.headeq` libraries, AutoEQ/Equalizer APO *ParametricEQ* files and Wavelet *GraphicEQ* files. Preset sync merges through iCloud Drive (or a folder you choose) and only ever adds items.

## Settings (⌘,)

- **General**: launch at login, automatic update checks and *Check now*.

- **Appearance**: color theme, Dock icon style (Classic, any theme, or *Match color theme*), show in Dock.
- **Menu Bar**: show/hide the icon, choose its style, show the current preset name.

## Troubleshooting

- **No sound / "Could not start"** — check the audio-capture permission, then switch the equalizer off and on.
- **Wrong device** — set Output to *System default* or the device you're listening on.
- **Bluetooth sounds worse during calls** — that's Bluetooth hands-free mode, not HeadEQ.
- **System Audio / Background Sounds controls missing** — your macOS version may have changed them; use the System Settings buttons.

## Privacy

Audio is processed locally and never leaves your Mac. The only network request is to the public AutoEQ repository on GitHub when you use *Add by Name…*. There is no telemetry.
