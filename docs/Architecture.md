# Architecture

```
Sources/EQCore/       Portable core — pure Swift, no Apple frameworks (libc math only)
Sources/HeadEQArt/    App icon + menu-bar glyph artwork (CoreGraphics)
Sources/make-icon/    Build tool: renders the .iconset
Sources/HeadEQ/       macOS app — SwiftUI UI, Core Audio tap backend, system integrations
Tests/EQCoreTests/    Unit tests for the core
```

## Signal chain

1. Preamp (auto = clip-safe)
2. Headphone correction (parametric biquads)
3. Graphic EQ (10 peaking bands)
4. Output stage — swap → crossfeed → width/mono → balance → polarity → gain
5. Hearing protection — spike guard + level cap
6. Peak limiter

All DSP is 32-bit float, allocation-free on the audio thread; parameters cross threads through a try-lock mailbox.

## macOS audio path

A global Core Audio **process tap** (macOS 14.2+) captures every process except HeadEQ and mutes the originals. A private **aggregate device** joins the tap with the chosen output; the IO proc runs `EQProcessor` and writes to the device.

## System integrations (private APIs)

Background Sounds (`HearingUtilities.HUComfortSoundsSettings`) and Headphone Accommodations (`PersonalAudio.PASettings`) have no public API. HeadEQ uses the same settings objects as System Settings through a guarded wrapper (`PrivateSettings`): every selector is checked and called through a typed IMP, so a future change degrades to "unavailable" rather than crashing.

## Porting

Each platform implements `AudioBackend` (and optionally `BackgroundSoundsBackend`); settings, presets, provenance, hearing protection, AutoEQ parsing and DSP are shared.

| Platform | Backend |
|---|---|
| iOS / iPadOS | `AVAudioEngine` for in-app playback (no system-wide EQ on iOS) |
| Android | `DynamicsProcessing` on the global session |
| Windows | WASAPI loopback + render, or an APO |
| Linux | PipeWire filter-chain |

## Versioning

`VERSION` holds the marketing version; the build number is `git rev-list --count HEAD`; the short commit hash is embedded as `HEQGitCommit` and shown in About. See `CHANGELOG.md`.
