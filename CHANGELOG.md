# Changelog

All notable changes to HeadEQ. Versions follow [Semantic Versioning](https://semver.org); the version lives in `VERSION`, and the build number is the git commit count.

## [0.5.0] — 2026-11-04
### Added
- **System Audio** page: device volume, mute and balance; alert volume; UI sound effects, volume-change feedback, flash screen on alert.
- **Headphone Accommodations** controls: on/off, tune for Balanced Tone / Vocal Range / Brightness, boost soft sounds; Transparency-mode customisation for connected AirPods (amplification, balance, tone, Conversation Boost).
- **Background Sounds EQ** (tinnitus filter pad: pitch 50 Hz–18 kHz × width, coarse/fine, ear balance) and a live **stop-timer countdown**.
- Labelled master **Equalizer On/Off** switch.
- Custom **app icon**, Dock icon styles (incl. match theme), Dock visibility, **menu-bar icon** choice and optional preset name (Settings ⌘,).
- **About** window, in-app searchable **Help** (⌘?), bundled **User Guide**, docs folder.
- Version control: git repository, `VERSION`, changelog, commit hash shown in About.

## [0.4.0] — 2026-11-04
### Changed
- Window reorganised into a sidebar with pages (Equalizer, Output, Hearing Protection, Background Sounds, Expert), each in two columns.
### Added
- macOS Accessibility **Background Sounds** controls (sound, volume, with-media volume, stop on lock, timer, tinnitus filter).

## [0.3.0] — 2026-10-13
### Added
- Sony WH-1000XM3 measured profile; **Add headphones by name** via the AutoEQ database with offline starter profiles.
- **Expert** page: tuning provenance (measured / approximation / generic / yours / modified), filter tables, signal chain, Equalizer APO export.
- **Hearing protection**: sudden-loudness guard, max-level cap, daily dose meter (NIOSH).

## [0.2.0] — 2026-10-13
### Added
- Custom headphone editor with live audition; editable user presets; describe-to-preset generator.
- Spectrum/bars/wave visualizer; eight colour themes.
- Output stage: gain, balance, width, mono, swap, polarity, crossfeed, peak limiter; graphic-EQ Q and fine steps; device sample rate.

## [0.1.0] — 2026-10-13
### Added
- System-wide EQ via Core Audio process tap; 10-band graphic EQ; headphone correction profiles; music presets; auto preamp; menu bar extra.
- Portable `EQCore` package (DSP, presets, backend protocol).
